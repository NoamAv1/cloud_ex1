#!/bin/bash
from flask import Flask, request
from datetime import datetime, timedelta
import random
import subprocess
import os

app = Flask(__name__)

empty_table = b' ticketid | plate | parkinglot | entry_time \n----------+-------+------------+------------\n(0 rows)\n\n'
entry_time_remove = b'         entry_time         \n----------------------------\n '
plate_remove = b' plate \n-------\n '
parking_lot_remove = b' parkinglot \n------------\n '

# Getting the account details for the DB and deleting it for security measures
f = open("/home/ubuntu/address.txt", "r")
address = f.readline().split('\n')[0]
username = f.readline().split('\n')[0]
password = f.readline().split('\n')[0]
os.remove("/home/ubuntu/address.txt")

def db_call(str):
    connect_to_db = "PGPASSWORD={}  psql -h {} -p 5432 -U {} -c".format(password, address, username)
    proc = subprocess.Popen(connect_to_db + '"' + str + '"', shell=True, stdout=subprocess.PIPE, )
    output = proc.communicate()[0]

    return output

@app.route('/')
def home():
    hello = "Hello and welcome to Roy's and Noam's cloud parking lot! <br/>"
    entry_str = "To use enter a car to our system please add to the URL \entry?plate=<plate number>&parkingLot=<parking " \
            "lot number> <br/> And you will get the ticket id <br/>"
    exit_str = "To get the price of the car that left please add to the URL \exit?ticketId=<ticket id> <br/> And you " \
               "will get the pricing for that car <br/> "

    return hello + entry_str + exit_str

@app.route('/entry')
def entry():
    # Getting arguments
    plate = request.args.get('plate')
    parking_lot = request.args.get('parkingLot')
    ticketId = str(random.randint(1000, 9999))

    # Check if car already parked
    is_plate_exist = db_call("select * from parkingSystem where plate='{}'".format(plate))
    if is_plate_exist != empty_table:
        return "This car already parking!"

    # Check if the ticketId is unique
    is_ticketId_exist = db_call("select * from parkingSystem where ticketId='{}'".format(ticketId))
    while is_ticketId_exist != empty_table:
        ticketId = str(random.randint(1000, 9999))
        is_ticketId_exist = db_call("select * from parkingSystem where ticketId='{}'".format(ticketId))

    # Park the car and return ticketId
    db_call("insert into parkingSystem(ticketId, plate, parkingLot, entry_time) values ('{}', '{}', '{}', '{}')".format(ticketId, plate, parking_lot, datetime.now()))

    return "The new ticket id is:" + str(ticketId)


@app.route('/exit')
def exit_func():
    # Get the ticketId argument
    ticketId = request.args.get('ticketId')

    # Check if the ticketId exist
    is_ticketId_exist = db_call("select * from parkingSystem where ticketId='{}'".format(ticketId))
    if is_ticketId_exist == empty_table:
        return "Ticket id doesn't exist on the system"

    # Calculate the charge
    entry_time = db_call("select entry_time from parkingSystem where ticketId='{}'".format(ticketId))[len(entry_time_remove):-10]
    entry_time = str(entry_time)[2:-1].split('.')[0]

    duration = datetime.now() - datetime.strptime(entry_time, '%Y-%m-%d %H:%M:%S')
    total_sec = int(duration.total_seconds())
    price = (int((total_sec / 60) / 15)) * 2.5

    # Return message
    time_string = str(duration).split(".")[0]
    plate_str = db_call("select plate from parkingSystem where ticketId='{}'".format(ticketId))[len(plate_remove):-10]
    plate_str = str(plate_str)[2:-1]
    parking_str = db_call("select parkingLot from parkingSystem where ticketId='{}'".format(ticketId))[len(parking_lot_remove):-10]
    parking_str = str(parking_str)[2:-1]

    string_msg = "The license plate is: " + plate_str + \
                 "<br/> The total parked time is: " + time_string + \
                 "<br/> The parking lot is: " + parking_str + \
                 "<br/> The price is: " + str(price)
    thank_you_msg = "<br/> Hope to see you again!"

    # Remove car from the parking lot
    db_call("delete from parkingSystem where ticketId='{}'".format(ticketId))

    return string_msg + thank_you_msg
