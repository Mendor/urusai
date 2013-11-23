-module (urusai_http_handler).

-behaviour (cowboy_http_handler).

-export ([init/3, handle/2, terminate/3]).

init(_Type, Req, _Opts) ->
    {ok, Req, undefined_state}.
 
handle(Req, State) ->
    {Method, _} = cowboy_req:method(Req),
    {Code, Message} = reply(Req, Method),
    {ok, Req2} = cowboy_req:reply(Code, [
        {<<"content-type">>, <<"application/json; charset=utf-8">>}
    ], Message, Req),
    {ok, Req2, State}.
 
terminate(_Reason, _Req, _State) ->
    ok.

reply(Req, <<"POST">>) ->
    {ok, ReqBody, _Req} = cowboy_req:body(Req),
    lager:info("Received HTTP API request: ~s", [ReqBody]),
    case jsonx:decode(ReqBody, [{format, proplist}]) of
        {error, Error, Pos} ->
            {200, jsonx:encode([{result, error},
                {message, list_to_binary(io_lib:format("~s (at ~B)", [Error, Pos]))}])};
        Decoded ->
            [Type, Target, Body] =
                [ proplists:get_value(K, Decoded) || K <- [<<"type">>, <<"target">>, <<"body">>] ],
            {Result, Message} = call_xmpp(Type, Target, Body),
            {200, jsonx:encode([{result, Result}, {message, Message}])}
    end;
reply(_Req, _) ->
    {405, <<>>}.

call_xmpp(_Type, undefined, _Body) ->
    {error, target_not_set};
call_xmpp(_Type, _Target, undefined) ->
    {error, body_not_set};
call_xmpp(<<"message">>, Target, Body) ->
    Result = gen_server:call(urusai_xmpp, {api_message, Target, Body}),
    {ok, Result};
call_xmpp(<<"plugin">>, Target, Body) ->
    gen_server:call(urusai_xmpp, {api_plugin, Target, Body});
call_xmpp(_Type, _Target, _Body) ->
    {error, unknown_message_type}.
