#!/usr/bin/python3

# import concurrent.futures
import logging
# import queue
import random
# import threading
import time
from datetime import datetime, date, timedelta

import requests
import xml

if __name__ == "__main__":
  format = "%(asctime)s: %(message)s"
  logging.basicConfig(level=logging.DEBUG, format='%(asctime)s.%(msecs)03d %(levelname)s:\t%(message)s', datefmt='%H:%M:%S')

  try:
    while True:
      logging.debug("Loop ...")
      time.sleep(1)
  except KeyboardInterrupt:
    pass
    logging.info("Stop")
  finally:
    logging.debug("Cleaning Up")
