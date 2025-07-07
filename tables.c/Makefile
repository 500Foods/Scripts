# Makefile for tables C implementation
CC = gcc
CFLAGS = -Wall -Wextra -O2 -Wno-unused-parameter -Wno-unused-function -Wno-unused-variable $(shell pkg-config --cflags jansson)
LDFLAGS = $(shell pkg-config --libs jansson)
TARGET = tables
SOURCES = *.c

# Default target to build the executable
all: $(TARGET)

$(TARGET):
	$(CC) $(CFLAGS) $(SOURCES) -o $(TARGET) $(LDFLAGS)

# Clean build artifacts
clean:
	rm -f $(TARGET)

# Phony targets
.PHONY: all clean
