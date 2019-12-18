#!/bin/bash
#export DJANGO_CONF=/Users/blau/info_services/info.warehouse/trunk/django_xsede_warehouse/xsede_warehouse/settings_localdev.conf
#export PYTHONPATH=/Users/blau/info_services/info.warehouse/trunk/apps:/Users/blau/info_services/info.warehouse/trunk/django_xsede_warehouse
#python ./serialize_save.py
PYTHON=/soft/python-2.7.11/bin/python
export PYTHON
export LD_LIBRARY_PATH=/soft/python-2.7.11/lib
export PYTHONPATH=/soft/warehouse-1.0/PROD/django_xsede_warehouse
export DJANGO_CONF=/soft/warehouse-1.0/conf/settings_info_mgmt.conf
export DJANGO_SETTINGS_MODULE=xsede_warehouse.settings
$PYTHON /soft/warehouse-apps-1.0/Manage-XDCDB/PROD/sbin/route_XDCDB.py ${@:1}
