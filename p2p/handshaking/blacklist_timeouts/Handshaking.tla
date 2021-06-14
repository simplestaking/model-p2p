---------- MODULE Handshaking ----------

EXTENDS FiniteSets, Naturals

CONSTANTS
    BAD_NODES,      \* byzantine nodes
    GOOD_NODES,     \* nodes who follow the protocol
    MIN,            \* minimum desired connections
    MAX             \* maximum desired connections

VARIABLES
    blacklist,      \* each node's set of blacklisted peers
    connections,    \* each node's set of connections
    messages,       \* each node's set of messages
    recv_ack,       \* each node's set of peers from whom they have received an ack message
    recv_conn,      \* each node's set of peers from whom they have received a connection message
    recv_meta,      \* each node's set of peers from whom they have received a metadata message
    sent_ack,       \* each node's set of peers to whom they have sent an ack message
    sent_conn,      \* each node's set of peers to whom they have sent a connection message
    sent_meta,      \* each node's set of peers to whom they have sent a metadata message
    in_progress     \* each node's set of peers with whom they are actively establishing a connection

vars == <<blacklist, connections, messages, recv_ack, recv_conn, recv_meta, sent_ack, sent_conn, sent_meta, in_progress>>

ASSUME BAD_NODES \cap GOOD_NODES = {}
ASSUME MIN \in Nat /\ MIN > 0
ASSUME MAX \in Nat /\ MIN <= MAX /\ MAX < Cardinality(BAD_NODES \cup GOOD_NODES)
\* For combinatorial reasons, we must also have:
ASSUME Cardinality(GOOD_NODES) > MIN
ASSUME
    LET N == Cardinality(BAD_NODES \cup GOOD_NODES) IN
    IF N = 3 THEN MAX /= 1 ELSE MAX /= 2 /\ MAX /= N - 2

----

(***********)
(* Helpers *)
(***********)

conn_msg(from) == [ type |-> "conn", from |-> from ]

meta_msg(from) == [ type |-> "meta", from |-> from ]

ack_msg(from) == [ type |-> "ack", from |-> from ]

nack_msg(from) == [ type |-> "nack", from |-> from ]

Nodes == BAD_NODES \cup GOOD_NODES

Bad(n) == n \in BAD_NODES

Bad_messages == [ type : {"conn", "meta", "ack", "nack", "bad"}, from : BAD_NODES ]

Messages == [ type : {"conn", "meta", "ack", "nack"}, from : GOOD_NODES ] \cup Bad_messages

Num_connections(g) == Cardinality(connections[g])

Can_start_connection_attempt(g) == Num_connections(g) + Cardinality(in_progress[g]) < MAX

Blacklisted(g, n) == n \in blacklist[g]

Connected(g, h) == g \in connections[h] /\ h \in connections[g]

(***********)
(* Actions *)
(***********)

\* Good node actions

exit_handshaking(g, n) ==
    /\ blacklist' = [ blacklist EXCEPT ![g] = @ \cup {n}]
    /\ connections' = [ connections EXCEPT ![g] = @ \ {n} ]
    /\ messages' = [ messages EXCEPT ![g] = { msg \in @ : msg.from /= n } ]
    /\ recv_conn' = [ recv_conn EXCEPT ![g] = @ \ {n} ]
    /\ sent_conn' = [ sent_conn EXCEPT ![g] = @ \ {n} ]
    /\ recv_meta' = [ recv_meta EXCEPT ![g] = @ \ {n} ]
    /\ sent_meta' = [ sent_meta EXCEPT ![g] = @ \ {n} ]
    /\ recv_ack' = [ recv_ack EXCEPT ![g] = @ \ {n} ]
    /\ sent_ack' = [ sent_ack EXCEPT ![g] = @ \ {n} ]
    /\ in_progress' = [ in_progress EXCEPT ![g] = @ \ {n} ]

\* connection messages

send_conn_msg(g, n) ==
    /\ messages' = [ messages EXCEPT ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {conn_msg(g)} ]
    /\ sent_conn' = [ sent_conn EXCEPT ![g] = @ \cup {n} ]
    /\ in_progress' = [ in_progress EXCEPT ![g] = @ \cup {n} ]
    /\ UNCHANGED <<blacklist, connections, recv_ack, recv_conn, recv_meta, sent_ack, sent_meta>>

InitiateConnection == \E g \in GOOD_NODES, n \in Nodes :
    /\ g /= n
    /\ Can_start_connection_attempt(g)
    /\ n \notin blacklist[g]
    /\ n \notin connections[g]
    /\ n \notin recv_conn[g]
    /\ n \notin sent_conn[g]
    /\ n \notin recv_meta[g]
    /\ n \notin sent_meta[g]
    /\ n \notin recv_ack[g]
    /\ n \notin sent_ack[g]
    /\ n \notin in_progress[g]
    /\ n \notin { m.from : m \in messages[g] }
    /\ send_conn_msg(g, n)

RespondToConnectionMessage == \E g \in GOOD_NODES :
    \E msg \in { m \in messages[g] : m.type = "conn" } :
        LET n == msg.from IN
        /\ Can_start_connection_attempt(g)
        /\ CASE n \notin sent_conn[g] \cup recv_conn[g] ->
                    /\ messages' = [ messages EXCEPT
                                        ![g] = @ \ {msg},
                                        ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {conn_msg(g)} ]
                    /\ recv_conn' = [ recv_conn EXCEPT ![g] = @ \cup {n} ]
                    /\ sent_conn' = [ sent_conn EXCEPT ![g] = @ \cup {n} ]
                    /\ in_progress' = [ in_progress EXCEPT ![g] = @ \cup {n} ]
                    /\ UNCHANGED <<blacklist, connections, recv_ack, recv_meta, sent_ack, sent_meta>>
             [] n \in sent_conn[g] /\ n \notin recv_conn[g] ->
                    /\ messages' = [ messages EXCEPT
                                        ![g] = @ \ {msg},
                                        ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {meta_msg(g)} ]
                    /\ recv_conn' = [ recv_conn EXCEPT ![g] = @ \cup {n} ]
                    /\ sent_meta' = [ sent_meta EXCEPT ![g] = @ \cup {n} ]
                    /\ UNCHANGED <<blacklist, connections, recv_ack, recv_meta, sent_ack, sent_conn, in_progress>>
             [] OTHER -> exit_handshaking(g, n)

\* meta messages

exchange_meta(g, n, msg) ==
    LET type == msg.type IN
    IF n \in sent_meta[g]
    THEN /\ messages' = [ messages EXCEPT
                            ![g] = @ \ {msg},
                            ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {ack_msg(g)} ]
         /\ recv_meta' = [ sent_meta EXCEPT ![g] = @ \cup {n} ]
         /\ sent_ack' = [ sent_ack EXCEPT ![g] = @ \cup {n} ]
         /\ UNCHANGED <<blacklist, connections, recv_ack, recv_conn, sent_conn, sent_meta, in_progress>>
    ELSE /\ messages' = [ messages EXCEPT
                            ![g] = @ \ {msg},
                            ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {meta_msg(g)} ]
         /\ recv_meta' = [ recv_meta EXCEPT ![g] = @ \cup {n} ]
         /\ sent_meta' = [ sent_meta EXCEPT ![g] = @ \cup {n} ]
         /\ UNCHANGED <<blacklist, connections, recv_ack, recv_conn, sent_ack, sent_conn, in_progress>>

ExchangeMeta == \E g \in GOOD_NODES :
    \E msg \in { m \in messages[g] : m.type = "meta" } :
        LET n == msg.from IN
        /\ n \in recv_conn[g]
        /\ n \in sent_conn[g]
        /\ n \notin recv_meta[g]
        /\ n \notin recv_ack[g]
        /\ n \notin sent_ack[g]
        /\ n \in in_progress[g]
        /\ exchange_meta(g, n, msg)

\* ack/nack messages

exchange_ack(g, n, msg) ==
    LET type == msg.type IN
    IF n \in sent_ack[g]
    THEN /\ connections' = [ connections EXCEPT ![g] = @ \cup {n} ]
         /\ messages' = [ messages EXCEPT ![g] = @ \ {msg} ]
         /\ recv_ack' = [ recv_ack EXCEPT ![g] = @ \cup {n} ]
         /\ in_progress' = [ in_progress EXCEPT ![g] = @ \ {n} ]
         /\ UNCHANGED <<blacklist, recv_conn, recv_meta, sent_ack, sent_conn, sent_meta>>
    ELSE /\ connections' = [ connections EXCEPT ![g] = @ \cup {n} ]
         /\ messages' = [ messages EXCEPT
                            ![g] = @ \ {msg},
                            ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {ack_msg(g)} ]
         /\ recv_ack' = [ recv_ack EXCEPT ![g] = @ \cup {n} ]
         /\ sent_ack' = [ sent_ack EXCEPT ![g] = @ \cup {n} ]
         /\ in_progress' = [ in_progress EXCEPT ![g] = @ \ {n} ]
         /\ UNCHANGED <<blacklist, recv_conn, recv_meta, sent_conn, sent_meta>>

ExchangeAck == \E g \in GOOD_NODES :
    \E msg \in { m \in messages[g] : m.type = "ack" } :
        LET n == msg.from IN
        /\ n \in sent_conn[g]
        /\ n \in recv_conn[g]
        /\ n \in sent_meta[g]
        /\ n \in recv_meta[g]
        /\ n \notin recv_ack[g]
        /\ n \in in_progress[g]
        /\ exchange_ack(g, n, msg)

nack(g, n, msg) ==
    /\ blacklist' = [ blacklist EXCEPT ![g] = @ \cup {n} ]
    /\ connections' = [ connections EXCEPT ![g] = @ \ {n} ]
    /\ messages' = [ messages EXCEPT
                        ![g] = { m \in @ : m.from /= n },
                        ![n] = IF Bad(n) \/ Blacklisted(n, g) THEN @ ELSE @ \cup {nack_msg(g)} ]
    /\ recv_conn' = [ recv_conn EXCEPT ![g] = @ \ {n} ]
    /\ sent_conn' = [ sent_conn EXCEPT ![g] = @ \ {n} ]
    /\ recv_meta' = [ recv_meta EXCEPT ![g] = @ \ {n} ]
    /\ sent_meta' = [ sent_meta EXCEPT ![g] = @ \ {n} ]
    /\ recv_ack' = [ recv_ack EXCEPT ![g] = @ \ {n} ]
    /\ sent_ack' = [ sent_ack EXCEPT ![g] = @ \ {n} ]
    /\ in_progress' = [ in_progress EXCEPT ![g] = @ \ {n} ]

Nack == \E g \in GOOD_NODES :
    \E msg \in { m \in messages[g] : m.type \in { "ack", "meta" } } :
        LET n == msg.from IN
        /\ Num_connections(g) >= MIN
        /\ n \notin connections[g]
        /\ n \in sent_conn[g]
        /\ n \in recv_conn[g]
        /\ nack(g, n, msg)

HandleNack == \E g \in GOOD_NODES :
    \E msg \in { m \in messages[g] : m.type = "nack" } :
        LET n == msg.from IN
        /\ n \notin connections[g]
        /\ n \in sent_conn[g]
        /\ n \in recv_conn[g]
        /\ exit_handshaking(g, n)

HandleBad == \E g \in GOOD_NODES :
    \/ \E msg \in { m \in messages[g] : m.type = "bad" } :
        LET n == msg.from IN exit_handshaking(g, n)
    \/ \E msg \in { m \in messages[g] : m.type \notin { "conn", "nack" } } :
        LET n == msg.from IN
        /\ n \notin recv_conn[g]
        /\ exit_handshaking(g, n)
    \/ \E msg \in { m \in messages[g] : m.type \notin { "meta", "nack" } } :
        LET n == msg.from IN
        /\ n \in recv_conn[g]
        /\ n \in sent_conn[g]
        /\ n \notin recv_meta[g]
        /\ exit_handshaking(g, n)
    \/ \E msg \in { m \in messages[g] : m.type \notin { "ack", "nack" } } :
        LET n == msg.from IN
        /\ n \in sent_conn[g]
        /\ n \in recv_conn[g]
        /\ n \in sent_meta[g]
        /\ n \in recv_meta[g]
        /\ n \notin recv_ack[g]
        /\ exit_handshaking(g, n)

\* Undesirable actions

\* bad node action
BadNodeSendsGoodNodeMessage == \E g \in GOOD_NODES :
    \E msg \in Bad_messages :
        LET n == msg.from IN
        /\ ~Blacklisted(g, n)
        /\ messages' = [ messages EXCEPT ![g] = @ \cup {msg} ]
        /\ UNCHANGED <<blacklist, connections, recv_ack, recv_conn, recv_meta, sent_ack, sent_conn, sent_meta, in_progress>>

Timeout == \E g \in GOOD_NODES :
    \/ \E n \in in_progress[g] : exit_handshaking(g, n)
    \/ \E n \in connections[g] :
        /\ g \notin connections[n]
        /\ exit_handshaking(g, n)

(*****************)
(* Specification *)
(*****************)

Init ==
    /\ blacklist = [ n \in Nodes |-> {} ]
    /\ connections = [ n \in Nodes |-> {} ]
    /\ messages = [ n \in Nodes |-> {} ]
    /\ recv_conn = [ n \in Nodes |-> {} ]
    /\ sent_conn = [ n \in Nodes |-> {} ]
    /\ recv_meta = [ n \in Nodes |-> {} ]
    /\ sent_meta = [ n \in Nodes |-> {} ]
    /\ recv_ack = [ n \in Nodes |-> {} ]
    /\ sent_ack = [ n \in Nodes |-> {} ]
    /\ in_progress = [ n \in Nodes |-> {} ]

Next ==
    \/ InitiateConnection
    \/ RespondToConnectionMessage
    \/ ExchangeMeta
    \/ ExchangeAck
    \/ Nack
    \/ HandleNack
    \/ HandleBad
    \/ BadNodeSendsGoodNodeMessage
    \/ Timeout

Fairness ==
    /\ WF_vars(InitiateConnection)
    /\ WF_vars(RespondToConnectionMessage)
    /\ WF_vars(ExchangeAck)
    /\ WF_vars(ExchangeMeta)
    /\ WF_vars(Nack)
    /\ WF_vars(HandleNack)
    /\ WF_vars(HandleBad)
    /\ WF_vars(BadNodeSendsGoodNodeMessage)
    /\ WF_vars(Timeout)

Spec == Init /\ [][Next]_vars /\ Fairness

(*********************)
(* Invariants/Safety *)
(*********************)

TypeOK ==
    /\ blacklist \in [ Nodes -> SUBSET Nodes ]
    /\ connections \in [ Nodes -> SUBSET Nodes ]
    /\ messages \in [ Nodes -> SUBSET Messages ]
    /\ recv_conn \in [ Nodes -> SUBSET Nodes ]
    /\ sent_conn \in [ Nodes -> SUBSET Nodes ]
    /\ recv_meta \in [ Nodes -> SUBSET Nodes ]
    /\ sent_meta \in [ Nodes -> SUBSET Nodes ]
    /\ recv_ack \in [ Nodes -> SUBSET Nodes ]
    /\ sent_ack \in [ Nodes -> SUBSET Nodes ]
    /\ in_progress \in [ Nodes -> SUBSET Nodes ]

NoSelfInteractions == \A g \in GOOD_NODES :
    /\ g \notin blacklist[g]
    /\ g \notin connections[g]
    /\ g \notin { msg.from : msg \in messages[g] }
    /\ g \notin recv_conn[g]
    /\ g \notin sent_conn[g]
    /\ g \notin recv_meta[g]
    /\ g \notin sent_meta[g]
    /\ g \notin recv_ack[g]
    /\ g \notin sent_ack[g]
    /\ g \notin in_progress[g]

GoodNodesDoNotExceedMaxConnections ==
    \A g \in GOOD_NODES : Num_connections(g) + Cardinality(in_progress[g]) <= MAX

GoodNodesNeverHaveMessagesFromBlacklistedPeers ==
    \A g \in GOOD_NODES : { msg \in messages[g] : msg.from \in blacklist[g] } = {}

GoodNodesHaveExlcusiveInProgressAndConnections ==
    \A g \in GOOD_NODES : in_progress[g] \cap connections[g] = {}

GoodNodesOnlyConnectToNodesWithWhomTheyHaveExchangedAllMessages ==
    \A g \in GOOD_NODES :
        connections[g] \subseteq recv_conn[g] \cap sent_conn[g] \cap recv_meta[g] \cap sent_meta[g] \cap recv_ack[g] \cap sent_ack[g]

GoodNodesOnlyExchangeMetaMessagesAfterSendingAndReceivingConnectionMessages ==
    \A g \in GOOD_NODES : recv_meta[g] \cup sent_meta[g] \subseteq recv_conn[g] \cap sent_conn[g]

GoodNodesOnlyExchangeAckMessagesAfterSendingAndReceivingConnectionAndMetaMessages ==
    \A g \in GOOD_NODES : recv_ack[g] \cup sent_ack[g] \subseteq recv_conn[g] \cap sent_conn[g] \cap recv_meta[g] \cap sent_meta[g]

Safety ==
    /\ NoSelfInteractions
    /\ GoodNodesDoNotExceedMaxConnections
    /\ GoodNodesNeverHaveMessagesFromBlacklistedPeers
    /\ GoodNodesHaveExlcusiveInProgressAndConnections
    /\ GoodNodesOnlyConnectToNodesWithWhomTheyHaveExchangedAllMessages
    /\ GoodNodesOnlyExchangeMetaMessagesAfterSendingAndReceivingConnectionMessages
    /\ GoodNodesOnlyExchangeAckMessagesAfterSendingAndReceivingConnectionAndMetaMessages

\* inductive invariant
IndInv == TypeOK /\ Safety

(***********************)
(* Properties/Liveness *)
(***********************)

OnceConnectedAlwaysConnected == \A g, h \in GOOD_NODES : Connected(g, h) ~> []Connected(g, h)

OnceBlacklistedAlwaysBlacklisted == \A g \in GOOD_NODES, n \inNodes : Blacklisted(g, n) ~> []Blacklisted(g, n)

GoodNodesEventuallyExceedMinConnections ==
    <>[](\A g \in GOOD_NODES :
        Cardinality(Nodes \ (blacklist[g] \cup {g})) >= MIN => Num_connections(g) >= MIN)

GoodNodesAlwaysRespondToAckMessagesOrBlacklist == \A g, h \in GOOD_NODES :
    \/ /\ ack_msg(h) \in messages[g]
       /\ h \notin sent_ack[g]
       ~> \/ ack_msg(g) \in messages[h]
          \/ Blacklisted(g, h)
    \/ /\ ack_msg(h) \in messages[g]
       /\ h \in sent_ack[g]
       ~> \/ Connected(g, h)
          \/ Blacklisted(g, h)

GoodNodesAlwaysRespondToMetaMessagesOrBlacklist == \A g, h \in GOOD_NODES :
    \/ /\ meta_msg(h) \in messages[g]
       /\ h \notin sent_meta[g]
       ~> \/ meta_msg(g) \in messages[h]
          \/ Blacklisted(g, h)
    \/ /\ meta_msg(h) \in messages[g]
       /\ h \in sent_meta[g]
       ~> \/ ack_msg(g) \in messages[h]
          \/ Blacklisted(g, h)

GoodNodesAlwaysRespondToConnectionMessagesOrBlacklist == \A g, h \in GOOD_NODES :
    \/ /\ conn_msg(h) \in messages[g]
       /\ h \notin sent_conn[g]
       ~> \/ conn_msg(g) \in messages[h]
          \/ Blacklisted(g, h)
    \/ /\ conn_msg(h) \in messages[g]
       /\ h \in sent_conn[g]
       ~> \/ meta_msg(g) \in messages[h]
          \/ Blacklisted(g, h)

ConnectionsBetweenGoodNodesAreEventuallyBidirectionalOrClosed == \A g, h \in GOOD_NODES :
    \/ g \in connections[h]
    \/ h \in connections[g]
    ~> \/ Connected(g, h)
       \/ [](g \notin connections[h] /\ h \notin connections[g])

Liveness ==
    /\ OnceConnectedAlwaysConnected
    /\ OnceBlacklistedAlwaysBlacklisted
    /\ GoodNodesEventuallyExceedMinConnections
    /\ GoodNodesAlwaysRespondToAckMessagesOrBlacklist
    /\ GoodNodesAlwaysRespondToMetaMessagesOrBlacklist
    /\ GoodNodesAlwaysRespondToConnectionMessagesOrBlacklist
    /\ ConnectionsBetweenGoodNodesAreEventuallyBidirectionalOrClosed

========================================
