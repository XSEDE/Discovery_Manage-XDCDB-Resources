#!/bin/bash
APP_BASE=/soft/warehouse-apps-1.0/Manage-XDCDB
APP_SOURCE=${APP_BASE}/PROD
WAREHOUSE_SOURCE=/soft/warehouse-1.0/PROD

PYTHON_BASE=${APP_BASE}/`cat python/lib/python*/orig-prefix.txt`
export LD_LIBRARY_PATH=${PYTHON_BASE}/lib

PIPENV_BASE=${APP_BASE}/python
source ${PIPENV_BASE}/bin/activate

export PYTHONPATH=${WAREHOUSE_SOURCE}/django_xsede_warehouse
export DJANGO_CONF=${APP_BASE}/conf/django_xsede_warehouse.conf
export DJANGO_SETTINGS_MODULE=xsede_warehouse.settings

${PIPENV_BASE}/bin/python ${APP_SOURCE}/sbin/route_xdcdb.py ${@:1}
