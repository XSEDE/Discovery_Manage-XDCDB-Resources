#!/usr/bin/env python

import pprint
import os
import pwd
import re
import sys
import argparse
import logging
import logging.handlers
import signal
import datetime
from datetime import datetime, tzinfo, timedelta
from time import sleep
import httplib
import json
import csv
import ssl
import shutil

import django
django.setup()
from django.utils.dateparse import parse_datetime
from xdcdb.models import *
from django.core import serializers
from processing_status.process import ProcessingActivity

#default_file = '/soft/warehouse-apps-1.0/Manage-XDCDB/var/tgresources.csv'
default_file = './tgresources.csv'
#snarfing the whole database is not the way to do it, for this anyway)
databasestate = serializers.serialize("json", TGResource.objects.all())
dbstate = json.loads(databasestate)
dbhash = {}
for obj in dbstate:
    #print obj
    dbhash[str(obj['pk'])]=obj
with open(default_file, 'r') as my_file:
    tgcdb_csv = csv.DictReader(my_file)
    for row in tgcdb_csv:
        if row['ResourceID'] in dbhash.keys():
            dbhash.pop(row['ResourceID'])
            #print len(dbhash.keys())
            #if row['project_number']+row['ResourceID'] in dbhash.keys():
            #    print "something is wrong"
        
        objtoserialize={}
        objtoserialize["model"]="xdcdb.TGResource"
        objtoserialize["pk"]=row['ResourceID']
        objtoserialize["fields"]=row
        jsonobj = json.dumps([objtoserialize])
        modelobjects =serializers.deserialize("json", jsonobj)

        for obj in modelobjects:
            obj.save()
            pa_application=os.path.basename(__file__)
            pa_function='Warehouse_XDCDB'
            pa_topic = 'XDCDB'
            pa_id = pa_topic+":"+objtoserialize["pk"]
            pa_about = 'project_affiliation=XSEDE'
            pa = ProcessingActivity(pa_application, pa_function, pa_id , pa_topic, pa_about)
        
    #print dbhash.keys()
    #print len(dbhash.keys())
    #delete leftover entries
    for key in dbhash.keys():
        #print dbhash[key]
        TGResource.objects.filter(pk=dbhash[key]['pk']).delete()
