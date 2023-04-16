#define NTHREADS 2
#define MAX_MSGS 2
#define IS_TOTAL
byte time = 1;
byte messages_sent = 0;
byte idx_1;
byte idx_2;
#ifdef IS_TOTAL
byte idx_3;
byte idx_4;
#endif

byte c_no;

#ifdef IS_TOTAL
byte c_no2;
#endif

typedef message {
    byte seq_no; // important that seq_no is first
    byte server_id;
    byte time_sent;
};

typedef message_channel {
    chan messages = [MAX_MSGS] of {message}
};


typedef client_messages {
    message messages[MAX_MSGS];
    byte size = 0;
};

typedef holdback_queue {
    chan hb_messages = [MAX_MSGS] of {message}
    byte curr_no = 0;
};

message_channel proxy_channels[2];
client_messages clients[NTHREADS];
message_channel server_messages[NTHREADS];


proctype proxy(byte id) {
    message m;
start:
    proxy_channels[id].messages?m;
    byte i;
    for (i : 0 .. NTHREADS - 1) {
        server_messages[i].messages!m;
    }
    goto start;
end:
    skip;
}

proctype server(byte id) {
    byte counter = 0;
    message m;
    holdback_queue holdbacks[NTHREADS];
    clients[id].size = 0;

check_messages:
    if
    :: empty(server_messages[id].messages) ->
        goto create_message;
    :: nempty(server_messages[id].messages) ->
        // send message to client
        byte s_id;
        atomic {
            message rec_m;
            server_messages[id].messages?rec_m;
            s_id = rec_m.server_id;
            holdbacks[s_id].hb_messages!!rec_m;
        }
    poll_holdback:
        if
        :: empty(holdbacks[s_id].hb_messages) ->
            goto create_message;
        :: nempty(holdbacks[s_id].hb_messages) ->
            message first_m;
            holdbacks[s_id].hb_messages?first_m;
            if
            :: first_m.seq_no == holdbacks[s_id].curr_no ->
                byte index = clients[id].size;
                if
                :: (index >= MAX_MSGS) -> goto end;
                :: else -> skip;
                fi
                atomic {
                    clients[id].messages[index].server_id = first_m.server_id;
                    clients[id].messages[index].seq_no = first_m.seq_no;
                    clients[id].messages[index].time_sent = first_m.time_sent;
                    clients[id].size = clients[id].size + 1;
                    holdbacks[s_id].curr_no++;
                }
                goto poll_holdback;
            :: else -> 
                // still waiting
                holdbacks[s_id].hb_messages!!first_m;
                goto check_messages;
            fi
        fi
    fi
create_message:
    atomic {
        if
        :: (messages_sent >= MAX_MSGS) -> goto check_messages;
        :: else -> skip;
        fi
        m.seq_no = counter;
        counter++;
        m.server_id = id;
        m.time_sent = time;
        time++;
        bool proxy_no;
        select(proxy_no : 0 .. 1);
        proxy_channels[proxy_no].messages!m;
        messages_sent++;
    }
    goto check_messages;
end:
    skip;
}


init {
    // init the data structures
    select(idx_1 : 0 .. MAX_MSGS - 1);
    select(idx_2 : 0 .. MAX_MSGS - 1);

    select(c_no : 0 .. NTHREADS - 1);

    #ifdef IS_TOTAL
    select(idx_3 : 0 .. MAX_MSGS - 1);
    select(idx_4 : 0 .. MAX_MSGS - 1);
    select(c_no2 : c_no .. NTHREADS - 1);
    #endif

    run proxy(0);
    run proxy(1);
    byte i = 0;
    atomic {
        for (i : 0 .. NTHREADS - 1) {
            run server(i);
        }
    }
}   

ltl unordered {
    [] (<> (clients[c_no].size == time -1));
}

ltl fifo_ordering {
    [] ((
        idx_1 < idx_2 
        // check if both messages are initialized
        && clients[c_no].messages[idx_1].time_sent > 0
        && clients[c_no].messages[idx_2].time_sent > 0
        // check if they've come from the same server
        && clients[c_no].messages[idx_1].server_id == 
        clients[c_no].messages[idx_2].server_id
        && idx_1 < idx_2
        )
        ->
        clients[c_no].messages[idx_1].time_sent <=
        clients[c_no].messages[idx_2].time_sent
    );
}

#ifdef IS_TOTAL
ltl total_ordering {
    [] (
        c_no != c_no2
        && clients[c_no].messages[idx_1].time_sent > 0
        && clients[c_no].messages[idx_2].time_sent > 0
        && idx_1 < idx_2
        && clients[c_no].messages[idx_1].time_sent == clients[c_no2].messages[idx_3].time_sent
        && clients[c_no].messages[idx_2].time_sent == clients[c_no2].messages[idx_4].time_sent
        ->
        idx_3 < idx_4
    );
}
#endif
