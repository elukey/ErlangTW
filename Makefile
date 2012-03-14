all:
	make clean	
	erlc -I include/ -o ebin/ src/*.erl
clean:
	rm -rf ebin/*.beam

