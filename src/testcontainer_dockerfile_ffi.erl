-module(testcontainer_dockerfile_ffi).
-export([run_docker_build/4]).

%% Cap accumulated build output at 10 MB to bound memory.
-define(MAX_OUTPUT_BYTES, 10485760).

run_docker_build(DockerfilePath, ContextPath, BuildArgs, TimeoutMs) ->
    case os:find_executable("docker") of
        false ->
            {error, <<"DOCKER_NOT_FOUND">>};
        Docker ->
            BaseArgs = [
                "build", "-f", binary_to_list(DockerfilePath),
                "--quiet", "--no-cache"
            ],
            ArgFlags = lists:flatmap(
                fun({K, V}) ->
                    [
                        "--build-arg",
                        binary_to_list(K) ++ "=" ++ binary_to_list(V)
                    ]
                end,
                BuildArgs
            ),
            AllArgs = BaseArgs ++ ArgFlags ++ [binary_to_list(ContextPath)],
            try
                Port = erlang:open_port(
                    {spawn_executable, Docker},
                    [
                        exit_status, binary, use_stdio,
                        stderr_to_stdout, {args, AllArgs}
                    ]
                ),
                collect_output(Port, <<>>, TimeoutMs)
            catch
                Class:Reason ->
                    Msg = io_lib:format("port spawn failed: ~p:~p", [Class, Reason]),
                    {error, list_to_binary(Msg)}
            end
    end.

collect_output(Port, Acc, TimeoutMs) ->
    receive
        {Port, {data, Data}} ->
            NewAcc = <<Acc/binary, Data/binary>>,
            case byte_size(NewAcc) > ?MAX_OUTPUT_BYTES of
                true ->
                    Truncated = binary:part(NewAcc, 0, ?MAX_OUTPUT_BYTES),
                    Marker = <<"\n[output truncated at 10MB]">>,
                    collect_output(Port, <<Truncated/binary, Marker/binary>>, TimeoutMs);
                false ->
                    collect_output(Port, NewAcc, TimeoutMs)
            end;
        {Port, {exit_status, 0}} ->
            Trimmed = string:trim(Acc),
            Lines = binary:split(Trimmed, <<"\n">>, [global]),
            LastLine = lists:last(Lines),
            {ok, LastLine};
        {Port, {exit_status, Code}} ->
            Trimmed = string:trim(Acc),
            Reason = format_exit_reason(Code, Trimmed),
            {error, Reason}
    after TimeoutMs ->
        try erlang:port_close(Port) of
            _ -> ok
        catch
            _:_ -> ok
        end,
        Msg = io_lib:format("docker build timed out after ~Bms", [TimeoutMs]),
        {error, list_to_binary(Msg)}
    end.

format_exit_reason(Code, Output) ->
    Prefix = case Code of
        125 -> <<"docker daemon error: ">>;
        126 -> <<"docker not executable: ">>;
        127 -> <<"docker not found: ">>;
        _   -> Prefix0 = io_lib:format("docker build exit ~B: ", [Code]),
               list_to_binary(Prefix0)
    end,
    case Output of
        <<>> -> Prefix;
        _    -> <<Prefix/binary, Output/binary>>
    end.
