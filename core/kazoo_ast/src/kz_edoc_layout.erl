%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2001-2018, 2600Hz
%%% The origin of this file is the edoc module `edoc_layout.erl'
%%% written by Richard Carlsson and Kenneth Lundin.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License"); you may
%%% not use this file except in compliance with the License. You may obtain
%%% a copy of the License at <http://www.apache.org/licenses/LICENSE-2.0>
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% Alternatively, you may use this file under the terms of the GNU Lesser
%%% General Public License (the "LGPL") as published by the Free Software
%%% Foundation; either version 2.1, or (at your option) any later version.
%%% If you wish to allow use of your version of this file only under the
%%% terms of the LGPL, you should delete the provisions above and replace
%%% them with the notice and other provisions required by the LGPL; see
%%% <http://www.gnu.org/licenses/>. If you do not delete the provisions
%%% above, a recipient may use your version of this file under the terms of
%%% either the Apache License or the LGPL.
%%%
%%%
%%% @doc This is the EDoc layout callback module for creating Kazoo
%%% documents in HTML format, and also application documents based on
%%% "overview.edoc". It parses and creates proplist of EDoc XML document
%%% and convert it to HTML using ErlyDTL template.
%%%
%%% copyright (c) 2600Hz 2018- . All Rights Reserved.
%%% @author Richard Carlsson <carlsson.richard@gmail.com>
%%% @author Hesaam Farhang <hesaam@2600hz.com>
%%% @end
%%%-----------------------------------------------------------------------------
-module(kz_edoc_layout).

-export([module/2
        ,overview/2

        ,get_elem/2
        ,get_attr/2
        ,get_attrval/2
        ,get_content/2
        ]).

-include_lib("xmerl/include/xmerl.hrl").

-type html_tag() :: atom().
-type html_attrib() :: [{atom(), string() | iolist() | atom() | integer()}].
-type exporty_thing() :: {html_tag(), html_attrib(), [exporty_thing()]} |
                         {html_tag(), exporty_thing()} |
                         html_tag() |
                         iolist() |
                         #xmlText{} |
                         #xmlElement{}.
-type exported() :: binary().

-define(NL, $\n).

-record(opts, {sort_functions = true :: boolean()
              ,encoding = utf8 :: atom()
              ,export_type = xmerl_html :: atom()
              ,pretty_printer = '' :: atom()
              }).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec module(#xmlElement{}, #opts{} | proplists:proplist()) -> iolist().
module(#xmlElement{name = module, content = Es}=E
      ,#opts{sort_functions = SortFunctions}=Opts
      ) ->
    Name = get_attrval(name, E),

    Functions = case [{function_name_arity(F, Opts), F} || F <- get_content(functions, Es)] of
                    Funs when SortFunctions =:= true -> lists:sort(Funs);
                    Funs -> Funs
                end,
    Types = [{type_name(T, Opts), T} || T <- get_content(typedecls, Es)],

    filter_empty(
      [{name, list_to_binary(Name)}
      ,{copyright, export_content(get_content(copyright, Es), Opts)}
      ,{deprecated, deprecated(Es, Opts)}
      ,{version, export_content(get_content(version, Es), Opts)}
      ,{since, since(Es, Opts)}
      ,{behaviours, behaviours_prop(Es, Name, Opts)}
      ,{authors, authors(Es, Opts)}
      ,{references, [export_content(C, Opts) || #xmlElement{content = C} <- get_elem(reference, Es)]}
      ,{sees, sees(Es, Opts)}
      ,{todos, todos(Es, Opts)}
      ,{types, types(lists:sort(Types), Opts)}
      ,{functions, functions(Functions, Opts)}
       | description(both, Es, Opts)
      ]);
module(E, Opts) ->
    module(E, init_opts(E, Opts)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec overview(#xmlElement{}, #opts{} | proplists:proplist()) -> iolist().
overview(#xmlElement{name = overview, content = Es}, #opts{}=Opts) ->
    filter_empty(
      [{title, export_content(get_text(title, Es), Opts)}
      ,{copyright, export_content(get_content(copyright, Es), Opts)}
      ,{version, export_content(get_content(version, Es), Opts)}
      ,{since, since(Es, Opts)}
      ,{authors, authors(Es, Opts)}
      ,{references, [export_content(C, Opts) || #xmlElement{content = C} <- get_elem(reference, Es)]}
      ,{sees, sees(Es, Opts)}
      ,{todos, todos(Es, Opts)}
      ,{full_desc, description(full, Es, Opts)}
      ]
     );
overview(E, Opts) ->
    overview(E, init_opts(E, Opts)).

%%%=============================================================================
%%% Module Tags functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Behaviour tag to proplist.
%% @end
%%------------------------------------------------------------------------------
-spec behaviours_prop([#xmlElement{}], string(), #opts{}) ->
                             Result when Result :: [{name, string()} |
                                                    {behaviours, [exported()]} |
                                                    {callbacks, [exported()]} |
                                                    {optional_callbacks, [exported()]}
                                                   ].
behaviours_prop(Es, BehaviourName, Opts) ->
    Behaviours = [export_content(behaviour(B)) || B <- get_elem(behaviour, Es)],
    Required = [export_content(callback(C, Opts)) || C <- get_content(callbacks, Es)],
    Optional = [export_content(callback(C, Opts)) || C <- get_content(optional_callbacks, Es)],
    case Required =/= []
        orelse Optional =/= []
    of
        true ->
            filter_empty([{name, BehaviourName}
                         ,{behaviours, Behaviours}
                         ,{callbacks, Required}
                         ,{optional_callbacks, Optional}
                         ]);
        false ->
            filter_empty([{behaviours, Behaviours}])
    end.

-spec behaviour(#xmlElement{}) -> [exporty_thing()].
behaviour(E=#xmlElement{content = Es}) ->
    see(E, Es).

-spec callback(#xmlElement{}, #opts{}) -> [string()].
callback(E=#xmlElement{}, Opts) ->
    Name = get_attrval(name, E),
    Arity = get_attrval(arity, E),
    [atom(Name, Opts), "/", Arity].

%%------------------------------------------------------------------------------
%% @doc Author proplist.
%% @end
%%------------------------------------------------------------------------------

-type author() :: [{name, binary()} |
                   {email, binary()} |
                   {website, binary()}
                  ].
-spec authors([#xmlElement{}], #opts{}) -> [{binary(), author()}].
authors(Es, Opts) ->
    lists:usort([{proplists:get_value(name, Author), Author}
                 || A <- get_elem(author, Es),
                    Author <- [author(A, Opts)],
                    Author =/= []
                ]).

-spec author(#xmlElement{}, #opts{}) -> author().
author(E=#xmlElement{}, _Opts) ->
    Email = iolist_to_binary(get_attrval(email, E)),
    URL = iolist_to_binary(get_attrval(website, E)),
    case get_attrval(name, E) of
        [] -> [];
        Name ->
            filter_empty([{name, iolist_to_binary(Name)}
                         ,{email, Email}
                         ,{website, URL}
                         ])
    end.

%%%=============================================================================
%%% Type Tag functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec type_name(#xmlElement{}, #opts{}) -> string().
type_name(#xmlElement{content = Es}, Opts) ->
    t_name(get_elem(erlangName, get_content(typedef, Es)), Opts).

%% <!ELEMENT typedecl (typedef, description?)>
%% <!ELEMENT typedef (erlangName, argtypes, type?, localdef*)>

-type typedef() :: [{def, exported()} |
                    {localdefs, localdefs()} |
                    {abstract_datatype, boolean()}
                   ].

-type type_prop() :: [{id, binary()} |
                      {label, string()} |
                      {typedef, typedef()} |
                      {full_desc, exported()}
                     ].

-spec types([#xmlElement{}], #opts{}) -> [type_prop()].
types(Ts, Opts) ->
    [typedecl(Name, E, Opts) || {Name, E} <- Ts].

-spec typedecl(string(), #xmlElement{}, #opts{}) -> type_prop().
typedecl(Name, E=#xmlElement{content = Es}, Opts) ->
    NameArgTypes = lists:append([Name, "("] ++ seq(t_utype_elem_fun(Opts), get_content(argtypes, Es), [")"])),
    {Id, _} = anchor_id_label(Name ++ "()", E),
    filter_empty(
      [{id, Id}
      ,{label, NameArgTypes}
      ,{typedef, typedef(NameArgTypes, get_content(typedef, Es), Opts)}
      ,{full_desc, description(full, Es, Opts)}
      ]
     ).

-spec typedef(string(), [#xmlElement{}], #opts{}) -> typedef().
typedef(NameArgTypes, Es, Opts) ->
    Typedef = filter_empty([{localdefs, local_defs(get_elem(localdef, Es), Opts)}]),

    case get_elem(type, Es) of
        [] ->
            [{def, export_content(NameArgTypes, Opts)}
            ,{abstract_datatype, true}
             | Typedef
            ];
        Type ->
            [{def, format_type(NameArgTypes, NameArgTypes, Type, Opts)} | Typedef]
    end.

-spec format_type(string(), string(), [#xmlElement{}], #opts{}) -> exported().
format_type(Prefix, NameArgTypes, Type, #opts{pretty_printer = erl_pp}=Opts) ->
    try
        L = t_utype(Type, Opts),
        O = pp_type(NameArgTypes, Type, Opts),
        {R, ".\n"} = etypef(L, O, Opts),
        export_content([Prefix] ++ [" = "] ++ R, Opts)
    catch _:_ ->
            %% Example: "t() = record(a)."
            io:format("wtf type ~p~n", [Prefix]),
            format_type(Prefix, NameArgTypes, Type, Opts#opts{pretty_printer =''})
    end;
format_type(Prefix, _Name, Type, Opts) ->
    export_content([Prefix] ++ [" = "] ++ t_utype(Type, Opts), Opts).

pp_type(Prefix, Type, Opts) ->
    Atom = list_to_atom(lists:duplicate(string:len(Prefix), $a)),
    Attr = {attribute, 0, type, {Atom, ot_utype(Type), []}},
    L1 = erl_pp:attribute(erl_parse:new_anno(Attr)
                         ,[{encoding, Opts#opts.encoding}]
                         ),
    {L2,N} = case lists:dropwhile(fun(C) -> C =/= $: end, lists:flatten(L1)) of
                 ":: " ++ L3 -> {L3, 9}; %% compensation for extra "()" and ":"
                 "::\n" ++ L3 -> {"\n" ++ L3, 6}
             end,
    Ss = lists:duplicate(N, $\s),
    S1 = re:replace(L2, "\n" ++ Ss, "\n", [{return,list},global,unicode]),

    %% remove the extra tickie if the atom must have tickies to
    %% avoid escaped tickies like (#'\'queue.declare'\'{}).
    re:replace(S1, "\\\\'", "", [{return,list},global,unicode]).

-type localdef() :: exported().
-type localdefs() :: [localdef()].

-spec local_defs([#xmlElement{}], #opts{}) -> localdefs().
local_defs(Es, Opts) ->
    [localdef(E1, Opts) || E1 <- Es].

-spec localdef(#xmlElement{}, #opts{}) -> localdef().
localdef(E = #xmlElement{content = Es}, Opts) ->
    {{_, Name}, TypeName} =
        case get_elem(typevar, Es) of
            [] ->
                N0 = lists:append(t_abstype(get_content(abstype, Es), Opts)),
                {anchor_id_label(N0, E), N0};
            [V] ->
                N0 = lists:append(t_var(V)),
                {{<<>>, N0}, N0}
        end,
    format_type(Name, TypeName, get_elem(type, Es), Opts).

%%%=============================================================================
%%% Function Tags functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec function_name_arity(#xmlElement{}, #opts{}) -> string().
function_name_arity(E, Opts) ->
    atom(get_attrval(name, E), Opts) ++ "/" ++ get_attrval(arity, E).

%% <!ELEMENT function (args, typespec?, returns?, throws?, equiv?,
%%                     description?, since?, deprecated?, see*, todo?)>
%% <!ATTLIST function
%%   name CDATA #REQUIRED
%%   arity CDATA #REQUIRED
%%   exported NMTOKEN(yes | no) #REQUIRED
%%   label CDATA #IMPLIED>
%% <!ELEMENT args (arg*)>
%% <!ELEMENT equiv (expr, see?)>
%% <!ELEMENT expr (#PCDATA)>

-type throws() :: [{type, exported()} | {localdefs, localdefs()}].
-type params() :: [{string(), exported()}].
-type function_props() :: [{id, binary()} |
                           {label, string()} |
                           {name, string()} |
                           {arity, string()} |
                           {is_exported, boolean()} |
                           {typespec, exported()} |
                           {localdefs, localdefs()} |
                           {params, params()} |
                           {returns, exported()} |
                           {throws, throws()} |
                           {equiv, exported()} |
                           {deprecated, exported()} |
                           {since, exported()} |
                           {sees, [exported()]} |
                           {todos, [exported()]} |
                           {short_desc, exported()} |
                           {full_desc, exported()}
                          ].

-spec functions([#xmlElement{}], #opts{}) -> [function_props()].
functions(Fs, Opts) ->
    [function(NameArity, E, Opts) || {NameArity, E} <- Fs].

-spec function(string(), #xmlElement{}, #opts{}) -> function_props().
function(NameArity, E=#xmlElement{content = Es}, Opts) ->
    Name = get_attrval(name, E),
    Arity = get_attrval(arity, E),
    {Id, Label} = anchor_id_label(NameArity, E),
    filter_empty(
      [{id, Id}
      ,{label, Label}
      ,{name, Name}
      ,{arity, Arity}
      ,{is_exported, is_exported(E)}
      ,{typespec, typespec_signature(E, Opts)}
      ,{localdefs, local_defs(get_elem(localdef, get_content(typespec, Es)), Opts)}
      ,{params, params(Es, Opts)}
      ,{returns, returns(Es, Opts)}
      ,{throws, throws(Es, Opts)}
      ,{equiv, equiv(Es, Opts)}
      ,{deprecated, deprecated(Es, Opts)}
      ,{since, since(Es, Opts)}
      ,{sees, sees(Es, Opts)}
      ,{todos, todos(Es, Opts)}
       | description(both, Es, Opts)
      ]
     ).

-spec is_exported(#xmlElement{}) -> boolean().
is_exported(E) ->
    case get_attrval(exported, E) of
        "yes" -> true;
        _ -> false
    end.

%% parameter descriptions (if any)
-spec params([#xmlElement{}], #opts{}) -> params().
params(Es, Opts) ->
    [{get_text(argName, Es1), Desc}
     || #xmlElement{content = Es1} <- get_content(args, Es),
        Desc <- [description(full, Es1, Opts)],
        Desc =/= <<>>
    ].

%% return value descriptions (if any)
-spec returns([#xmlElement{}], #opts{}) -> exported().
returns(Es, Opts) ->
    description(full, get_content(returns, Es), Opts).

%% <!ELEMENT throws (type, localdef*)>

-spec throws([#xmlElement{}], #opts{}) -> throws().
throws(Es, Opts) ->
    case get_content(throws, Es) of
        [] -> [];
        Es1 ->
            %% Don't use format_type; keep it short!
            [{type, export_content(t_utype(get_elem(type, Es1), Opts), Opts)}
            ,{localdefs, local_defs(get_elem(localdef, Es1), Opts)}
            ]
    end.

-spec equiv([#xmlElement{}], #opts{}) -> exported().
equiv(Es, Opts) ->
    Es1 = get_content(equiv, Es),
    case {get_content(expr, Es1)
         ,get_elem(see, Es1)
         }
    of
        {[], _} -> <<>>;
        {[Expr], []} ->
            export_content(Expr, Opts);
        {[Expr], [E=#xmlElement{}]} ->
            export_content(see(E, [Expr]), Opts)
    end.

-spec typespec_signature(#xmlElement{}, #opts{}) -> exported().
typespec_signature(E=#xmlElement{content = Es}, Opts) ->
    case typespec(get_content(typespec, Es), Opts) of
        [] ->
            export_content(signature(get_content(args, Es), atom(get_attrval(name, E), Opts)), Opts);
        Spec ->
            export_content(Spec, Opts)
    end.

%% <!ELEMENT typespec (erlangName, type, localdef*)>

-spec typespec([#xmlElement{}], #opts{}) -> [string()].
typespec([], _Opts) -> [];
typespec(Es, Opts) ->
    Name = t_name(get_elem(erlangName, Es), Opts),
    [Type] = get_elem(type, Es),
    format_spec(Name, Type, Opts).

%% <!ELEMENT args (arg*)>
%% <!ELEMENT arg (argName, description?)>
%% <!ELEMENT argName (#PCDATA)>

%% This is currently only done for functions without type spec.

-spec signature([#xmlElement{}], string()) -> [string()].
signature(Es, Name) ->
    [Name, "("] ++ seq(fun function_arg/1, Es) ++ [") -> any()"].

-spec function_arg(#xmlElement{}) -> [string()].
function_arg(#xmlElement{content = Es}) ->
    [get_text(argName, Es)].

%% Use the default formatting of EDoc, which creates references, and
%% then insert newlines and indentation according to erl_pp (the
%% (fast) Erlang pretty printer).
format_spec(Name, Type, #opts{pretty_printer = erl_pp}=Opts) ->
    try
        L = t_clause(Name, Type, Opts),
        O = pp_clause(Name, Type, Opts),
        {R, ".\n"} = etypef(L, O, Opts),
        R
    catch _E:_T ->
            %% Should not happen.
            io:format("wtf spec ~p~n", [Name]),
            format_spec(Name, Type, Opts#opts{pretty_printer=''})
    end;
format_spec(Sep, Type, Opts) ->
    %% Very limited formatting.
    t_clause(Sep, Type, Opts).

t_clause(Name, Type, Opts) ->
    #xmlElement{content = [#xmlElement{name = 'fun', content = C}]} = Type,
    [Name] ++ t_fun(C, Opts).

pp_clause(Pre, Type, Opts) ->
    Types = ot_utype([Type]),
    Atom = lists:duplicate(string:len(Pre), $a),
    Attr = {attribute, 0, spec, {{list_to_atom(Atom), 0}, [Types]}},
    L1 = erl_pp:attribute(erl_parse:new_anno(Attr)
                         ,[{encoding, Opts#opts.encoding}
                          ]),
    "-spec " ++ L2 = lists:flatten(L1),
    L3 = Pre ++ lists:nthtail(length(Atom), L2),
    L4 = re:replace(L3, "\n      ", "\n", [{return,list},global,unicode]),

    %% remove the extra tickie if the atom must have tickies to
    %% avoid escaped tickies like (#'\'queue.declare'\'{}).
    re:replace(L4, "\\\\'", "", [{return,list},global,unicode]).

%%%=============================================================================
%%% Edoc typedef/spec_type Tags to HTML functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec t_utype([#xmlElement{}], #opts{}) -> any().
t_utype([E], Opts) ->
    t_utype_elem(E, Opts).

-spec t_utype_elem_fun(#opts{}) -> fun((#xmlElement{}) -> any()).
t_utype_elem_fun(Opts) ->
    fun(E) -> t_utype_elem(E, Opts) end.

-spec t_utype_elem(#xmlElement{}, #opts{}) -> any().
t_utype_elem(E=#xmlElement{content = Es}, Opts) ->
    case get_attrval(name, E) of
        "" -> t_type(Es, Opts);
        Name ->
            T = t_type(Es, Opts),
            case T of
                [Name] -> T; %% avoid generating "Foo::Foo"
                T -> [Name] ++ ["::"] ++ T
            end
    end.

t_type([E=#xmlElement{name = typevar}], _Opts) ->
    t_var(E);
t_type([E=#xmlElement{name = atom}], Opts) ->
    t_atom(E, Opts);
t_type([E=#xmlElement{name = integer}], _Opts) ->
    t_integer(E);
t_type([E=#xmlElement{name = range}], _Opts) ->
    t_range(E);
t_type([E=#xmlElement{name = binary}], _Opts) ->
    t_binary(E);
t_type([E=#xmlElement{name = float}], _Opts) ->
    t_float(E);
t_type([#xmlElement{name = nil}], _Opts) ->
    t_nil();
t_type([#xmlElement{name = paren, content = Es}], Opts) ->
    t_paren(Es, Opts);
t_type([#xmlElement{name = list, content = Es}], Opts) ->
    t_list(Es, Opts);
t_type([#xmlElement{name = nonempty_list, content = Es}], Opts) ->
    t_nonempty_list(Es, Opts);
t_type([#xmlElement{name = map, content = Es}], Opts) ->
    t_map(Es, Opts);
t_type([#xmlElement{name = tuple, content = Es}], Opts) ->
    t_tuple(Es, Opts);
t_type([#xmlElement{name = 'fun', content = Es}], Opts) ->
    ["fun("] ++ t_fun(Es, Opts) ++ [")"];
t_type([E = #xmlElement{name = record, content = Es}], Opts) ->
    t_record(E, Es, Opts);
t_type([E = #xmlElement{name = abstype, content = Es}], Opts) ->
    t_abstype(E, Es, Opts);
t_type([#xmlElement{name = union, content = Es}], Opts) ->
    t_union(Es, Opts).

t_var(E) ->
    [get_attrval(name, E)].

t_atom(E, Opts) ->
    [atom(get_attrval(value, E), Opts)].

t_integer(E) ->
    [get_attrval(value, E)].

t_range(E) ->
    [get_attrval(value, E)].

t_binary(E) ->
    [get_attrval(value, E)].

t_float(E) ->
    [get_attrval(value, E)].

t_nil() ->
    ["[]"].

t_paren(Es, Opts) ->
    ["("] ++ t_utype(get_elem(type, Es), Opts) ++ [")"].

t_list(Es, Opts) ->
    ["["] ++ t_utype(get_elem(type, Es), Opts) ++ ["]"].

t_nonempty_list(Es, Opts) ->
    ["["] ++ t_utype(get_elem(type, Es), Opts) ++ [", ...]"].

t_map(Es, Opts) ->
    Fs = get_elem(map_field, Es),
    ["#{"] ++ seq(fun(E) -> t_map_field(E, Opts) end, Fs, ["}"]).

t_map_field(#xmlElement{content = [K,V]}=E, Opts) ->
    KElem = t_utype_elem(K, Opts),
    VElem = t_utype_elem(V, Opts),
    AS = case get_attrval(assoc_type, E) of
             "assoc" -> " => ";
             "exact" -> " := "
         end,
    KElem ++ [AS] ++ VElem.

t_tuple(Es, Opts) ->
    ["{"] ++ seq(t_utype_elem_fun(Opts), Es, ["}"]).

-spec t_fun([#xmlElement{}], #opts{}) -> [exporty_thing()].
t_fun(Es, Opts) ->
    ["("] ++ seq(t_utype_elem_fun(Opts), get_content(argtypes, Es),
                 [") -> "] ++ t_utype(get_elem(type, Es), Opts)).

t_record(E, Es, Opts) ->
    Name = ["#"] ++ t_type(get_elem(atom, Es), Opts),
    case get_elem(field, Es) of
        [] ->
            see(E, Name ++ ["{}"]);
        Fs ->
            see(E, Name) ++ ["{"] ++ seq(fun(F) -> t_field(F, Opts) end, Fs, ["}"])
    end.

t_field(#xmlElement{content = Es}, Opts) ->
    t_type(get_elem(atom, Es), Opts) ++ [" = "] ++ t_utype(get_elem(type, Es), Opts).

t_abstype(E, Es, Opts) ->
    Name = t_name(get_elem(erlangName, Es), Opts),
    case get_elem(type, Es) of
        [] ->
            see(E, [Name, "()"]);
        Ts ->
            see(E, [Name]) ++ ["("] ++ seq(t_utype_elem_fun(Opts), Ts, [")"])
    end.

t_abstype(Es, Opts) ->
    [t_name(get_elem(erlangName, Es), Opts), "("]
        ++ seq(t_utype_elem_fun(Opts), get_elem(type, Es), [")"]).

t_union(Es, Opts) ->
    seq(t_utype_elem_fun(Opts), Es, " | ", []).

%%%=============================================================================
%%% Edoc typedef/spec_type Tags to Erlang AST functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec ot_utype(any()) -> any().
ot_utype([E]) ->
    ot_utype_elem(E).

ot_utype_elem(E=#xmlElement{content = Es}) ->
    case get_attrval(name, E) of
        "" -> ot_type(Es);
        N ->
            Name = {var,0,list_to_atom(N)},
            T = ot_type(Es),
            case T of
                Name -> T;
                T -> {ann_type,0,[Name, T]}
            end
    end.

ot_type([E=#xmlElement{name = typevar}]) ->
    ot_var(E);
ot_type([E=#xmlElement{name = atom}]) ->
    ot_atom(E);
ot_type([E=#xmlElement{name = integer}]) ->
    ot_integer(E);
ot_type([E=#xmlElement{name = range}]) ->
    ot_range(E);
ot_type([E=#xmlElement{name = binary}]) ->
    ot_binary(E);
ot_type([E=#xmlElement{name = float}]) ->
    ot_float(E);
ot_type([#xmlElement{name = nil}]) ->
    ot_nil();
ot_type([#xmlElement{name = paren, content = Es}]) ->
    ot_paren(Es);
ot_type([#xmlElement{name = list, content = Es}]) ->
    ot_list(Es);
ot_type([#xmlElement{name = nonempty_list, content = Es}]) ->
    ot_nonempty_list(Es);
ot_type([#xmlElement{name = tuple, content = Es}]) ->
    ot_tuple(Es);
ot_type([#xmlElement{name = map, content = Es}]) ->
    ot_map(Es);
ot_type([#xmlElement{name = 'fun', content = Es}]) ->
    ot_fun(Es);
ot_type([#xmlElement{name = record, content = Es}]) ->
    ot_record(Es);
ot_type([#xmlElement{name = abstype, content = Es}]) ->
    ot_abstype(Es);
ot_type([#xmlElement{name = union, content = Es}]) ->
    ot_union(Es).

ot_var(E) ->
    {var, 0, list_to_atom(get_attrval(name, E))}.

ot_atom(E) ->
    Name = list_to_atom(get_attrval(value, E)),
    {atom, erl_anno:new(0), Name}.

ot_integer(E) ->
    {integer, 0, list_to_integer(get_attrval(value, E))}.

ot_range(E) ->
    [I1, I2] = string:tokens(get_attrval(value, E), "."),
    {type, 0, range, [{integer, 0, list_to_integer(I1)}
                     ,{integer, 0, list_to_integer(I2)}
                     ]
    }.

ot_binary(E) ->
    {Base, Unit} =
        case string:tokens(get_attrval(value, E), ",:*><") of
            [] ->
                {0, 0};
            ["_", B] ->
                {list_to_integer(B), 0};
            ["_", "_", U] ->
                {0, list_to_integer(U)};
            ["_", B, _, "_", U] ->
                {list_to_integer(B), list_to_integer(U)}
        end,
    {type, 0, binary, [{integer, 0, Base}, {integer, 0, Unit}]}.

ot_float(E) ->
    {float, 0, list_to_float(get_attrval(value, E))}.

ot_nil() ->
    {nil, 0}.

ot_paren(Es) ->
    {paren_type, 0, [ot_utype(get_elem(type, Es))]}.

ot_list(Es) ->
    {type, 0, list, [ot_utype(get_elem(type, Es))]}.

ot_nonempty_list(Es) ->
    {type, 0, nonempty_list, [ot_utype(get_elem(type, Es))]}.

ot_tuple(Es) ->
    {type, 0, tuple, [ot_utype_elem(E) || E <- Es]}.

ot_map(Es) ->
    {type, 0, map, [ot_map_field(E) || E <- get_elem(map_field,Es)]}.

ot_map_field(#xmlElement{content=[K,V]}=E) ->
    A = case get_attrval(assoc_type, E) of
            "assoc" -> map_field_assoc;
            "exact" -> map_field_exact
        end,
    {type, 0, A, [ot_utype_elem(K), ot_utype_elem(V)]}.

ot_fun(Es) ->
    Range = ot_utype(get_elem(type, Es)),
    Args = [ot_utype_elem(A) || A <- get_content(argtypes, Es)],
    {type, 0, 'fun', [{type,0,product,Args},Range]}.

ot_record(Es) ->
    {type, 0, record, [ot_type(get_elem(atom, Es))
                       | [ot_field(F) || F <- get_elem(field, Es)]
                      ]
    }.

ot_field(#xmlElement{content = Es}) ->
    {type, 0, field_type, [ot_type(get_elem(atom, Es))
                          ,ot_utype(get_elem(type, Es))
                          ]
    }.

ot_abstype(Es) ->
    ot_name(get_elem(erlangName, Es)
           ,[ot_utype_elem(Elem) || Elem <- get_elem(type, Es)]
           ).

ot_union(Es) ->
    {type, 0, union, [ot_utype_elem(E) || E <- Es]}.

ot_name(Es, T) ->
    case ot_name(Es) of
        [Mod, ":", Atom] ->
            {remote_type, 0, [{atom, 0, list_to_atom(Mod)}
                             ,{atom,0,list_to_atom(Atom)},T
                             ]
            };
        "tuple" when T =:= [] ->
            {type, 0, tuple, any};
        Atom ->
            {type, 0, list_to_atom(Atom), T}
    end.

ot_name([E]) ->
    Atom = get_attrval(name, E),
    case get_attrval(module, E) of
        "" -> Atom;
        M ->
            case get_attrval(app, E) of
                "" -> [M, ":", Atom];
                A -> ["//" ++ A ++ "/" ++ M, ":", Atom] %% EDoc only!
            end
    end.

%%%=============================================================================
%%% Linkage functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec sees([#xmlElement{}], #opts{}) -> [exported()].
sees(Es, Opts) ->
    [export_content(see(E), Opts) || E <- get_elem(see, Es)].

-spec see(#xmlElement{}) -> [exporty_thing()].
see(E=#xmlElement{content = Es}) ->
    see(E, Es).

-spec see(#xmlElement{}, [#xmlElement{}] | [string()]) -> [exporty_thing()].
see(E, Es) ->
    case href(E) of
        [] -> Es;
        Ref ->
            [{a, Ref, Es}]
    end.

%% TODO: Modify links to Erlang module/behaviour and deps.
-spec href(#xmlElement{}) -> [{target, string()} | {href, string()}].
href(E) ->
    case get_attrval(href, E) of
        "" -> [];
        URI ->
            T = case get_attrval(target, E) of
                    "" -> [];
                    S -> [{target, S}]
                end,
            [{href, URI} | T]
    end.

-spec anchor_id_label(string() | binary() | [string()] | [binary()], #xmlElement{}) -> {binary(), string() | binary() | [string()] | [binary()]}.
anchor_id_label(Content, E) ->
    case get_attrval(label, E) of
        "" -> {<<>>, Content};
        Ref -> {iolist_to_binary(Ref), Content}
    end.

%%%=============================================================================
%%% Common Tags functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Deprecated tag to proplist.
%% @end
%%------------------------------------------------------------------------------
-spec deprecated([#xmlElement{}], #opts{}) -> exported().
deprecated(Es, Opts) ->
    description(full, get_content(deprecated, Es), Opts).

-spec description(full | both, [#xmlElement{}], #opts{}) -> exported() | [{short_desc | full_desc, exported()}].
description(full, Es, Opts) ->
    export_content(normalize_paragraphs(get_content(fullDescription, get_content(description, Es))), Opts);
%% description(short, Es, Opts) ->
%%     export_content(normalize_paragraphs(get_content(briefDescription, get_content(description, Es))), Opts);
description(both, Es, Opts) ->
    Desc = get_content(description, Es),
    Short = normalize_paragraphs(get_content(briefDescription, Desc)),
    Full = normalize_paragraphs(get_content(fullDescription, Desc)),
    % io:format("~n Full ~p~n", [Full]),
    filter_empty(
      [{short_desc, export_content(Short, Opts)}
      ,{full_desc, export_content(Full, Opts)}
      ]
     ).

-spec since([#xmlElement{}], #opts{}) -> exported().
since(Es, Opts) ->
    export_content(get_content(since, Es), Opts).

-spec todos([#xmlElement{}], #opts{}) -> [exported()].
todos(Es, Opts) ->
    [export_content(C, Opts) || #xmlElement{content = C} <- get_elem(todo, Es)].

%%------------------------------------------------------------------------------
%% @doc Replaces types with their link.
%% @end
%%------------------------------------------------------------------------------
-spec etypef(any(), any(), any()) -> any().
etypef(L, O0, Opts) ->
    {R, O} = etypef(L, [], O0, [], Opts),
    {lists:reverse(R), O}.

etypef([C | L], St, [C | O], R, Opts) ->
    etypef(L, St, O, [[C] | R], Opts);
etypef(" "++L, St, O, R, Opts) ->
    etypef(L, St, O, R, Opts);
etypef("", [Cs | St], O, R, Opts) ->
    etypef(Cs, St, O, R, Opts);
etypef("", [], O, R, _Opts) ->
    {R, O};
etypef(L, St, " "++O, R, Opts) ->
    etypef(L, St, O, [" " | R], Opts);
etypef(L, St, "\n"++O, R, Opts) ->
    Ss = lists:takewhile(fun(C) -> C =:= $\s end, O),
    etypef(L, St, lists:nthtail(length(Ss), O), ["\n"++Ss | R], Opts);
etypef([{a, HRef, S0} | L], St, O0, R, Opts) ->
    {S, O} = etypef(S0, app_fix(O0, Opts), Opts),
    etypef(L, St, O, [{a, HRef, S} | R], Opts);
etypef("="++L, St, "::"++O, R, Opts) ->
    %% EDoc uses "=" for record field types; Erlang types use "::".
    %% Maybe there should be an option for this, possibly affecting
    %% other similar discrepancies.
    etypef(L, St, O, ["=" | R], Opts);
etypef([Cs | L], St, O, R, Opts) ->
    etypef(Cs, [L | St], O, R, Opts).

app_fix(L, Opts) ->
    try
        {"//" ++ R1,L2} = app_fix1(L, 1),
        [App, Mod] = string:tokens(R1, "/"),
        "//" ++ atom(App, Opts) ++ "/" ++ atom(Mod, Opts) ++ L2
    catch _:_ -> L
    end.

app_fix1(L, I) -> % a bit slow
    {L1, L2} = lists:split(I, L),
    case erl_scan:tokens([], L1 ++ ". ", 1) of
        {done, {ok,[{atom,_,Atom}|_],_}, _} -> {atom_to_list(Atom), L2};
        _ -> app_fix1(L, I+1)
    end.

%%%=============================================================================
%%% XML Utility functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Export simple content of elements to HTML.
%% @end
%%------------------------------------------------------------------------------
-spec export_content(exporty_thing() | [exporty_thing()]) -> exported().
export_content(Es) ->
    export_content(Es, #opts{}).

-spec export_content(exporty_thing() | [exporty_thing()], #opts{}) -> exported().
export_content(Es, #opts{export_type = xmerl_html}) when is_list(Es) ->
    iolist_to_binary(xmerl:export_simple_content(Es, xmerl_html));
export_content(Es, #opts{}) when is_list(Es) ->
    iolist_to_binary(xmerl:export_simple_content(Es, xmerl_xml));
export_content(E, Opts) ->
    export_content([E], Opts).

-spec t_name([#xmlElement{}], #opts{}) -> string().
t_name([E], Opts) ->
    N = get_attrval(name, E),
    case get_attrval(module, E) of
        "" -> atom(N, Opts);
        M ->
            S = atom(M, Opts) ++ ":" ++ atom(N, Opts),
            case get_attrval(app, E) of
                "" -> S;
                A -> "//" ++ atom(A, Opts) ++ "/" ++ S
            end
    end.

-spec atom(string(), #opts{}) -> string().
%% Commenting until switching to Erlang-20
%% atom(String, #opts{encoding = latin1}) ->
%%     io_lib:write_atom_as_latin1(list_to_atom(strip_tickie(String)));
atom(String, #opts{encoding = utf8}) ->
    io_lib:write_atom(list_to_atom(strip_tickie(String))).

-spec strip_tickie(string()) -> string().
strip_tickie("'"++Rest) ->
    strip_tickie(Rest);
strip_tickie(String) ->
    case lists:last(String) of
        39 -> lists:droplast(String);
        _ -> String
    end.

%%------------------------------------------------------------------------------
%% @doc Why EDoc is so stupid to not make a paragraph of last text/markups
%% if they are not a block level elements?
%% This is a copy pasta code from `edoc_wiki' with a change to remove
%% stupid whitespace only `#xmlText{}'.
%% @end
%%------------------------------------------------------------------------------
-spec normalize_paragraphs([#xmlElement{}]) -> [exporty_thing()].
normalize_paragraphs(Es) ->
    normalize_paragraphs(Es, [], []).

-spec normalize_paragraphs([#xmlElement{}], [exporty_thing()], [exporty_thing()]) -> [exporty_thing()].
normalize_paragraphs([E=#xmlElement{name = Name}|Es], As, Bs) ->
    case Name of
        'p'          -> par_flush(Es, [E | As], Bs);
        'hr'         -> par_flush(Es, [E | As], Bs);
        'h1'         -> par_flush(Es, [E | As], Bs);
        'h2'         -> par_flush(Es, [E | As], Bs);
        'h3'         -> par_flush(Es, [E | As], Bs);
        'h4'         -> par_flush(Es, [E | As], Bs);
        'h5'         -> par_flush(Es, [E | As], Bs);
        'h6'         -> par_flush(Es, [E | As], Bs);
        'pre'        -> par_flush(Es, [E | As], Bs);
        'address'    -> par_flush(Es, [E | As], Bs);
        'div'        -> par_flush(Es, [E | As], Bs);
        'blockquote' -> par_flush(Es, [E | As], Bs);
        'form'       -> par_flush(Es, [E | As], Bs);
        'fieldset'   -> par_flush(Es, [E | As], Bs);
        'noscript'   -> par_flush(Es, [E | As], Bs);
        'ul'         -> par_flush(Es, [E | As], Bs);
        'ol'         -> par_flush(Es, [E | As], Bs);
        'dl'         -> par_flush(Es, [E | As], Bs);
        'table'      -> par_flush(Es, [E | As], Bs);
        _            -> normalize_paragraphs(Es, [E | As], Bs)
    end;
normalize_paragraphs([E=#xmlText{value = Value}|Es], As, Bs) ->
    case is_only_whitespace(Value) of
        true -> normalize_paragraphs(Es, As, Bs);
        false -> normalize_paragraphs(Es, [E | As], Bs)
    end;
normalize_paragraphs([], [], Bs) ->
    lists:reverse(Bs);
normalize_paragraphs([], As, Bs) ->
    lists:reverse([{p, lists:reverse(As)} | Bs]).

-spec par_flush([#xmlElement{}], [exporty_thing()], [exporty_thing()]) -> [exporty_thing()].
par_flush(Es, As, Bs) ->
    normalize_paragraphs(Es, [], As ++ Bs).

-spec get_elem(atom(), [#xmlElement{}]) -> [#xmlElement{}].
get_elem(Name, [#xmlElement{name = Name} = E | Es]) ->
    [E | get_elem(Name, Es)];
get_elem(Name, [_ | Es]) ->
    get_elem(Name, Es);
get_elem(_, []) ->
    [].

-spec get_attr(atom(), [#xmlAttribute{}]) -> [#xmlAttribute{}].
get_attr(Name, [#xmlAttribute{name = Name} = A | As]) ->
    [A | get_attr(Name, As)];
get_attr(Name, [_ | As]) ->
    get_attr(Name, As);
get_attr(_, []) ->
    [].

-spec get_attrval(atom(), #xmlElement{}) -> iolist() | atom() | integer().
get_attrval(Name, #xmlElement{attributes = As}) ->
    case get_attr(Name, As) of
        [#xmlAttribute{value = V}] ->
            V;
        [] -> ""
    end.

-spec get_content(atom(), [#xmlElement{}]) -> any().
get_content(Name, Es) ->
    case get_elem(Name, Es) of
        [#xmlElement{content = Es1}] ->
            Es1;
        [] -> []
    end.

-spec get_text(atom(), [#xmlElement{}]) -> string().
get_text(Name, Es) ->
    case get_content(Name, Es) of
        [#xmlText{value = Text}] ->
            Text;
        [] -> ""
    end.

%%%=============================================================================
%%% Utility functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Put layout options in a data structure for easier access.
%% @end
%%------------------------------------------------------------------------------
-spec init_opts(#xmlElement{} | atom(), proplists:proplist()) -> #opts{}.
init_opts(#xmlElement{}=Element, Options) ->
    Encoding = case get_attrval(encoding, Element) of
                   "latin1" -> latin1;
                   _ -> utf8
               end,
    init_opts(Encoding, Options);
init_opts(Encoding, Options) ->
    #opts{sort_functions = proplists:get_value(sort_functions, Options, true)
         ,encoding = Encoding
         ,export_type = proplists:get_value(export_type, Options, xmerl_html)
         ,pretty_printer = proplists:get_value(pretty_printer, Options, '')
         }.

-spec is_only_whitespace(string()) -> boolean().
is_only_whitespace([]) ->
    true;
is_only_whitespace([$\s | C]) ->
    is_only_whitespace(C);
is_only_whitespace([$\t | C]) ->
    is_only_whitespace(C);
is_only_whitespace([$\n | C]) ->
    is_only_whitespace(C);
is_only_whitespace(_) ->
    false.

-spec seq(fun((#xmlElement{}) -> exporty_thing()), [#xmlElement{}]) -> [exporty_thing()].
seq(F, Es) ->
    seq(F, Es, []).

-spec seq(fun((#xmlElement{}) -> exporty_thing()), [#xmlElement{}], [string()]) -> [exporty_thing()].
seq(F, Es, Tail) ->
    seq(F, Es, ", ", Tail).

-spec seq(fun((#xmlElement{}) -> exporty_thing()), [#xmlElement{}], string(), [string()]) -> [exporty_thing()].
seq(F, [E], _Sep, Tail) ->
    F(E) ++ Tail;
seq(F, [E | Es], Sep, Tail) ->
    F(E) ++ [Sep] ++ seq(F, Es, Sep, Tail);
seq(_F, [], _Sep, Tail) ->
    Tail.

-spec filter_empty([{atom(), list() | iolist() | binary()}]) -> [{atom(), list() | iolist() | binary()}].
filter_empty(Props) ->
    [P || P <- Props, is_not_empty(P)].

-spec is_not_empty({atom(), list() | iolist() | binary()}) -> boolean().
is_not_empty({_, []}) -> 'false';
is_not_empty({_, <<>>}) -> 'false';
is_not_empty(_V) -> 'true'.