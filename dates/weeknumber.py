#!/usr/bin/env python3

import sys
import datetime

def weeknumber(date):

  date = datetime.datetime.strptime(date, "%Y-%m-%d") if date else datetime.datetime.today()
  
  # Get Thursday of same week as date
  if date.weekday() == 6: # Sun
    wkdate = date + datetime.timedelta(days=4)
  elif date.weekday() == 0: # Mon 
    wkdate = date + datetime.timedelta(days=3)
  elif date.weekday() == 1: # Tue
    wkdate = date + datetime.timedelta(days=2)
  elif date.weekday() == 2: # Wed
    wkdate = date + datetime.timedelta(days=1)
  elif date.weekday() == 3: # Thu
    wkdate = date
  elif date.weekday() == 4: # Fri  
    wkdate = date - datetime.timedelta(days=1)
  else: # Sat
    wkdate = date - datetime.timedelta(days=2)

  week_num = wkdate.isocalendar()[1]

  day = date.day
  month = date.month 
  year = date.year
  day_of_week = date.strftime("%a")

  print(f"{year:04d}-{month:02d}-{day:02d} ({day_of_week}) W{week_num:02d}")
  
if __name__ == "__main__":
  if len(sys.argv) > 1:
    date = sys.argv[1]
  else:
    date = None
    
  weeknumber(date)

