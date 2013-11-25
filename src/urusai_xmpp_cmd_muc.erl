%%% Commands available by sending private messages by MUC owner.
%%%
-module (urusai_xmpp_cmd_muc).

-export ([cmd/3]).

cmd(_, <<"ping">>, []) ->
    {ok, <<"pong">>};
cmd(Muc, <<"w">>, []) ->
    {ok, <<"You're from ", Muc/binary>>};
cmd(Muc, <<"leave">>, []) ->
    gen_server:cast(urusai_xmpp, {muc_leave, Muc}),
    {ok, <<"As you wish.">>};
cmd(_, <<"plugins">>, []) ->
    {ok, <<"Allowed actions:\n\tlist\n\ttoggle <PLUGIN>">>};
cmd(Muc, <<"plugins">>, [Params]) ->
    [Action | Tail] = binary:split(Params, <<" ">>),
    MucK = <<"muc_plugins_", Muc/binary>>,
    case Action of
        <<"list">> ->
            AllPlugins = urusai_plugin:plugins(mucmessage),
            EnabledPlugins = urusai_db:get(MucK),
            Out = [ plugin_line(P, lists:member(P, EnabledPlugins)) || P <- AllPlugins ],
            {ok, list_to_binary(Out)};
        <<"toggle">> when Tail =:= [] ->
            error;
        <<"toggle">> ->
            [BP] = Tail,
            Plugin = list_to_atom(binary_to_list(BP)),
            AllPlugins = urusai_plugin:plugins(mucmessage),
            EnabledPlugins = urusai_db:get(MucK),
            Reply = case {lists:member(Plugin, EnabledPlugins), lists:member(Plugin, AllPlugins)} of
                {true, _} ->
                    urusai_db:set(MucK, lists:delete(Plugin, urusai_db:get(MucK))),
                    list_to_binary(io_lib:format("Plugin '~s' has been disabled for the room ~s", [Plugin, Muc]));
                {false, true} ->
                    urusai_db:set(MucK, lists:append(urusai_db:get(MucK), [Plugin])),
                    list_to_binary(io_lib:format("Plugin '~s' has been enabled for the room ~s", [Plugin, Muc]));
                {false, false} ->
                    list_to_binary(io_lib:format("There is no plugin '~s' found.", [Plugin]))
            end,
            {ok, Reply}
    end;
cmd(_, _, _) ->
    error.

plugin_line(Plugin, true) ->
    list_to_binary(io_lib:format("\n[X] ~p", [Plugin]));
plugin_line(Plugin, false) ->
    list_to_binary(io_lib:format("\n[_] ~p", [Plugin])).
