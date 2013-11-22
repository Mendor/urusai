%%% XMPP client. Need I say more?
%%%
-module (urusai_xmpp).

-behaviour (gen_server).

-define (SERVER, ?MODULE).
-define (CMD, urusai_xmpp_commands).

-include_lib ("deps/exmpp/include/exmpp.hrl").
-include_lib ("deps/exmpp/include/exmpp_client.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export ([start_link/0, connect/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    spawn_link(?MODULE, connect, []),
    {ok, state}.
handle_call({muc_join, Muc, Params}, _From, State) ->
    {reply, muc_join(State, Muc, Params), State};
handle_call({muc_leave, Muc}, _From, State) ->
    {reply, muc_leave(State, Muc), State};
handle_call({muc_nick, Muc, Nick}, _From, State) ->
    {reply, muc_nick(State, Muc, Nick), State};
handle_call({status, Message}, _From, State) ->
    {reply, status_message(State, Message), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({set_session, Session}, _State) ->
    {noreply, Session};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% XMPP client connector
connect() ->
    [GetUser, GetServer, Password, Resource, Port]
        = [ urusai_config:get(auth, K) || K <- [login, server, password, resource, port] ],

    [User | TServer] = string:tokens(GetUser, "@"),
    % If server is unset in configuration value, parse it from login string
    case GetServer of
        []                    -> [ConnServer] = TServer, Server = ConnServer;
        _ when TServer =/= [] -> ConnServer = GetServer, [Server] = TServer;
        _                     -> ConnServer = GetServer, Server = GetServer
    end,

    % TODO: implement SSL
    Session = exmpp_session:start(),
    JID = exmpp_jid:make(User, Server, Resource),
    lager:info("Trying to connect as ~s@~s to the server ~s:~B", [User, Server, ConnServer, Port]),
    urusai_db:set(<<"current_jid">>, JID), % required for alerts
    exmpp_session:auth_basic_digest(Session, JID, Password),
    ConnectMethod = case urusai_config:get(auth, ssl) of
        true  -> connect_SSL;
        false -> connect_TCP
    end,
    {ok, _Stream} = exmpp_session:ConnectMethod(Session, ConnServer, Port),
    exmpp_session:login(Session),
    lager:info("Connected."),
    update_status(Session),
    muc_autojoin(Session),
    gen_server:cast(?SERVER, {set_session, Session}),
    listen(Session).

%% Incoming packets listener
listen(MySession) ->
    receive
        stop ->
            exmpp_session:stop(MySession);
        Packet ->
            parse_packet(MySession, Packet),
            listen(MySession)
    end.

%% Send formed package
send_packet(Session, Message) ->
    lager:debug("[~p] -> ~p", [Session, Message]),
    exmpp_session:send_packet(Session, Message).

%% Parse received XMPP packet
parse_packet(Session, Packet) ->
    lager:debug("[~p] <- ~p", [Session, Packet]),
    case Packet of
        % MUC message
        #received_packet{packet_type=message,
                                  raw_packet=Raw,
                                  type_attr=Type} when Type =:= "groupchat" ->
            handle_muc_message(Session, Raw);
        % Private message
        #received_packet{packet_type=message,
                                  raw_packet=Raw,
                                  type_attr=Type} when Type =/= "error" ->
            handle_private(Session, Raw);
        % IQ message
        #received_packet{packet_type=iq,
                                  raw_packet=Raw,
                                  type_attr=_Type} ->
            handle_iq(Session, Raw);
        % Presence
        Record when Record#received_packet.packet_type == 'presence' ->
            handle_presence(Session, Record, Record#received_packet.raw_packet);
        _Other ->
            lager:error("Unknown packet received: ~p", [Packet])
    end.

%% MUC message handler
handle_muc_message(Session, Packet) ->
    From = exmpp_xml:get_attribute(Packet, <<"from">>, <<"unknown">>),
    [Muc, User] = binary:split(From, <<"/">>),
    handle_muc_message(Session, Packet, From, urusai_db:get(<<"muc_nick_", Muc/binary>>) =:= User).

handle_muc_message(_Session, _Packet, _From, true) ->
    ok;
handle_muc_message(Session, Packet, From, false) ->
    Me = exmpp_xml:get_attribute(Packet, <<"to">>, <<"unknown">>),
    Command = exmpp_message:get_body(Packet),
    case urusai_plugin:match(mucmessage, From, [], [Command]) of
        none    -> ok;
        Replies -> [send_packet(Session, make_muc_packet(Me, From, E)) || E <- Replies]
    end.

%% Private message handler
handle_private(Session, Packet) ->
    From = exmpp_xml:get_attribute(Packet, <<"from">>, <<"unknown">>),
    Me = exmpp_xml:get_attribute(Packet, <<"to">>, <<"unknown">>),
    handle_private(Session, Packet, is_owner(From), From, Me).

%% Parse private message if it has been sent by bot owner
handle_private(Session, Packet, true, Target, Me) ->
    Command = exmpp_message:get_body(Packet),
    [C | P] = binary:split(Command, <<" ">>),
    % In case owner want to execute some plugin command, he should send it with `exec ` prefix
    PBody = case ?CMD:cmd(C, P) of
        {ok, Reply} -> Reply;
        error       -> <<"Bad internal command.">>
    end,
    send_packet(Session, make_private_packet(Me, Target, PBody));
%% Or if it has been sent by somebody else
handle_private(Session, Packet, false, Target, Me) ->
    Command = exmpp_message:get_body(Packet),
    case urusai_plugin:match(private, Target, [], [Command]) of
        none -> 
            send_packet(Session, make_private_packet(Me, Target, <<"No such command.">>));
        Replies ->
            [send_packet(Session, make_private_packet(Me, Target, E)) || E <- Replies]
    end.

%% IQ handler
handle_iq(_Session, _Packet) ->
    % TODO: implement %)
    ok.

%% Presence handler
handle_presence(Session, Packet, _Presence) ->
    case exmpp_jid:make({Conf, Serv, _Nick} = Packet#received_packet.from) of
        JID ->
            case _Type = Packet#received_packet.type_attr of
                "available" ->
                    ok;
                "unavailable" ->
                    ok;
                "subscribe" ->
                    presence_subscribed(Session, JID),
                    presence_subscribe(Session, JID);
                "subscribed" ->
                    presence_subscribed(Session, JID),
                    presence_subscribe(Session, JID);
                "error" ->
                    alert(Session, <<"Failed to join MUC ", Conf/binary, "@", Serv/binary>>),
                    ok
            end
    end.

%% ----------------------------------------
%% Presence actions
%% ----------------------------------------

presence_subscribed(Session, Recipient) ->
    lager:info("Exchanging subscriptions with ~s", [Recipient]),
    Presence_Subscribed = exmpp_presence:subscribed(),
    Presence = exmpp_stanza:set_recipient(Presence_Subscribed, Recipient),
    send_packet(Session, Presence).

presence_subscribe(Session, Recipient) ->
    Presence_Subscribe = exmpp_presence:subscribe(),
    Presence = exmpp_stanza:set_recipient(Presence_Subscribe, Recipient),
    send_packet(Session, Presence).

%% ----------------------------------------
%% MUC actions
%% ----------------------------------------

make_muc_packet(Me, ConfUser, Body) ->
    To = exmpp_jid:bare_to_list(exmpp_jid:bare(exmpp_jid:parse(ConfUser))),
    exmpp_xml:set_attribute(
        exmpp_xml:set_attribute(
            exmpp_xml:set_attribute(
                exmpp_message:chat(Body), <<"from">>, Me), <<"to">>, To), <<"type">>, <<"groupchat">>).

muc_join(Session, Muc, Params) ->
    OldNick = urusai_db:get(<<"muc_nick_", Muc/binary>>),
    Nick = case Params of
        [] when OldNick =:= [] -> list_to_binary(urusai_config:get(muc, default_nick));
        []                     -> OldNick;
        _                      -> list_to_binary(Params)
    end,
    RP = exmpp_presence:set_status(exmpp_presence:available(), urusai_db:get(<<"status">>)),
    Presence = exmpp_xml:set_attribute(RP, <<"to">>, <<Muc/binary, "/", Nick/binary>>),
    send_packet(Session, Presence),
    lager:info("Joining MUC ~s as ~s", [Muc, Nick]),
    urusai_db:set(<<"autojoin">>, lists:usort(lists:append(urusai_db:get(<<"autojoin">>), [Muc]))),
    urusai_db:set(<<"muc_nick_", Muc/binary>>, Nick),
    {ok, <<"Presence sent.">>}.

muc_leave(Session, Muc) ->
    RP = exmpp_presence:set_status(exmpp_presence:unavailable(), "kthxbye"),
    Presence = exmpp_xml:set_attribute(RP, <<"to">>, <<Muc/binary>>),
    send_packet(Session, Presence),
    lager:info("Leaving MUC ~s", [Muc]),
    urusai_db:set(<<"autojoin">>, lists:delete(Muc, urusai_db:get(<<"autojoin">>))),
    {ok, <<"Presence sent.">>}.

muc_nick(Session, Muc, [Nick]) ->
    RP = exmpp_presence:set_status(exmpp_presence:available(), urusai_db:get(<<"status">>)),
    Presence = exmpp_xml:set_attribute(RP, <<"to">>, <<Muc/binary, "/", Nick/binary>>),
    send_packet(Session, Presence),
    lager:info("Changed nick at MUC ~s to ~s", [Muc, Nick]),
    urusai_db:set(<<"muc_nick_", Muc/binary>>, Nick),
    {ok, <<"Presence sent.">>}.

muc_autojoin(Session) ->
    [ muc_join(Session, A, []) || A <- urusai_db:get(<<"autojoin">>) ].

%% ----------------------------------------
%% Private messages actions
%% ----------------------------------------

make_private_packet(From, To, Body) ->
    exmpp_xml:set_attribute(
        exmpp_xml:set_attribute(
            exmpp_message:chat(Body), <<"from">>, From), <<"to">>, To).

%% Send alert 
alert(Session, Msg) ->
    lager:error("Alert: ~s", [Msg]),
    Me = exmpp_jid:bare_to_binary(urusai_db:get(<<"current_jid">>)),
    [ send_packet(Session, make_private_packet(Me, O, Msg)) || O <- urusai_db:get(<<"owners">>) ].

%% ----------------------------------------
%% Other
%% ----------------------------------------

%% Is JID on owners list?
is_owner(Jid) ->
    Bare = exmpp_jid:bare_to_list(exmpp_jid:bare(exmpp_jid:parse(Jid))),
    lists:member(Bare, urusai_db:get(<<"owners">>)).

%% Update status message trigger
status_message(Session, Msg) ->
    urusai_db:set(<<"status">>, Msg),
    update_status(Session),
    {ok, <<"Status message updated.">>}.

%% Update status message
update_status(Session) ->
    Msg = urusai_db:get(<<"status">>),
    send_packet(Session, exmpp_presence:set_status(exmpp_presence:available(), Msg)).
