#define NTHREADS 2
#define MAX_MSGS 3

byte time = 1;
byte messages_sent = 0;
byte proxy_sent = 0;


byte idx_1;
byte idx_2;
byte c_no;

typedef message {
    byte server_id;
    byte seq_no;
    byte time_sent;
};

typedef message_channel {
    chan messages = [MAX_MSGS] of {message}
};


typedef client_messages {
    message messages[MAX_MSGS];
    byte size = 0;
};

message_channel proxy_channels[2];
client_messages clients[NTHREADS];
message_channel server_messages[NTHREADS];


proctype proxy(byte id) {
    message m;
start:
    proxy_channels[id].messages?m;
    atomic {
        byte i;
        for (i : 0 .. NTHREADS - 1) {
            server_messages[i].messages!m;
            
        }
        proxy_sent++;
    }
    goto start;
end:
    skip;
}

proctype server(byte id) {
    byte counter = 0;
    clients[id].size = 0;
    message m;
check_messages:
    atomic {
        if
        :: (clients[id].size >= MAX_MSGS) -> goto end;
        :: else -> skip;
        fi
    }

    if
    :: empty(server_messages[id].messages) ->
        goto create_message;
    :: nempty(server_messages[id].messages) ->
        // send message to client
        atomic {
            message rec_m;
            server_messages[id].messages?rec_m;
            byte index = clients[id].size;
            // assign message
            clients[id].messages[index].server_id = rec_m.server_id;
            clients[id].messages[index].seq_no = rec_m.seq_no;
            clients[id].messages[index].time_sent = rec_m.time_sent;
            clients[id].size = clients[id].size + 1;
        }
        goto check_messages;
    fi

    
create_message:
    atomic {
        if
        :: (messages_sent >= MAX_MSGS) -> goto check_messages;
        :: (messages_sent < MAX_MSGS) -> skip;
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
        if
        :: (clients[id].size >= MAX_MSGS) -> goto end;
        :: else -> goto check_messages;
        fi
    }
end:
    skip;
}

init {
    // init the data structures
    select(idx_1 : 0 .. MAX_MSGS - 1);
    select(idx_2 : idx_1 + 1 .. MAX_MSGS - 1);
    select(c_no : 0 .. NTHREADS - 1);
    run proxy(0);
    run proxy(1);
    byte i;
    for (i : 0 .. NTHREADS - 1) {
        run server(i);
    }
    //run server(2);
}   

ltl unordered {
    <> (clients[c_no].size == MAX_MSGS);
}

ltl fifo_ordering {
    [] ((
        // check if both messages are initialized
        clients[c_no].messages[idx_1].time_sent > 0
        && clients[c_no].messages[idx_2].time_sent > 0
        // check if they've come from the same server
        && clients[c_no].messages[idx_1].server_id ==  clients[c_no].messages[idx_2].server_id
        )
        ->
        clients[c_no].messages[idx_1].time_sent <=
        clients[c_no].messages[idx_2].time_sent
    );
}
