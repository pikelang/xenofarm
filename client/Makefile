all: put

put: put.o
	@$(CC) -o put put.o 2>/dev/null || \
	$(CC) -o put put.o -lnsl -lsocket 2>/dev/null || \
	$(CC) -o put put.o -lnsl && \
	echo "Successfully built put." || \
	echo "Failed to build put."

clean:
	rm -rf put put.o
