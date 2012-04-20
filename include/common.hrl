-record(message, {type, seqNumber, lpSender, lpReceiver, payload, timestamp}).
-record(lp_status, {my_id, 
					received_messages, 
					inbox_messages, 
					max_received_messages,
					proc_messages, 
					sent_messages, 
					to_ack_messages, 
					anti_messages, 
					current_event,
					history, gvt, 
					rollbacks, timestamp,
					model_state, 
					init_model_state,
					samadi_find_mode, 
					samadi_marked_messages_min, 
					messageSeqNumber, status}).
-record(sent_msgs, {event, msgs_list}).