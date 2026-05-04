-module(test_helpers_ffi).
-export([getenv/1]).

getenv(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        "" -> {error, nil};
        Value -> {ok, list_to_binary(Value)}
    end.
