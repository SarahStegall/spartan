-module(dcos_dns_sup).
-author("Christopher Meiklejohn <christopher.meiklejohn@gmail.com>").

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-include("dcos_dns.hrl").

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    ZkRecordServer = {dcos_dns_zk_record_server,
                      {dcos_dns_zk_record_server, start_link, []},
                       permanent, 5000, worker,
                       [dcos_dns_zk_record_server]},
    ConfigLoaderServer =
        #{
            id => dcos_dns_config_loader_server,
            start => {dcos_dns_config_loader_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [dcos_dns_config_loader_server]
        },

    HandlerSup = #{
        id => dcos_dns_handler_sup,
        start => {dcos_dns_handler_sup, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => supervisor,
        modules => [dcos_dns_handler_sup]
    },

    %% Configure metrics.
    dcos_dns_metrics:setup(),

    Children = [HandlerSup, ZkRecordServer, ConfigLoaderServer],
    Children1 = maybe_add_udp_servers(Children),
    {ok, { {one_for_all, 0, 1}, Children1} }.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private
maybe_add_udp_servers(Children) ->
    case application:get_env(?APP, udp_server_enabled, true) of
        true ->
            udp_servers() ++ Children;
        false ->
            Children
    end.

udp_servers() ->
    {ok, Iflist} = inet:getifaddrs(),
    Addresses = lists:foldl(fun fold_over_if/2, [], Iflist),
    lists:map(fun udp_server/1, Addresses).

fold_over_if({_Ifname, IfOpts}, Acc) ->
    IfAddresses = [Address || {addr, Address = {_, _, _, _}} <- IfOpts],
    ordsets:union(ordsets:from_list(IfAddresses), Acc).

udp_server(Address) ->
    #{
        id => {dcos_dns_udp_server, Address},
        start => {dcos_dns_udp_server, start_link, [Address]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [dcos_dns_udp_server]
    }.