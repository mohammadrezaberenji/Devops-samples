#! /usr/bin/env python3
import time
import sys

print("Simple service is starting up .." , flush=True)

while True:
    print("Simple service is doing background work..." , flush=True)
    time.time_ns()
    time.sleep(5)
