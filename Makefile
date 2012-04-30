ERL_BIN_DIR=/usr/bin

all:
	make clean	
	$(ERL_BIN_DIR)/erlc -I include/ -o ebin/ src/*.erl
clean:
	rm -rf ebin/*.beam

