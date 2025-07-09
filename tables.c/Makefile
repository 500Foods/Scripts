# Makefile for tables C implementation
CC = gcc
CFLAGS = -Wall -Wextra -O2 $(shell pkg-config --cflags jansson)
LDFLAGS = $(shell pkg-config --libs jansson)
TARGET = tables
SOURCES = *.c

# Default target to build the executable, ensuring clean is run first
all: clean $(TARGET)

$(TARGET):
	$(CC) $(CFLAGS) $(SOURCES) -o $(TARGET) $(LDFLAGS)

# Clean build artifacts
clean:
	rm -f $(TARGET)

# Phony targets
.PHONY: all clean
