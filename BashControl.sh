v#!/bin/bash

# ---------- Declarations ---------------------------------------------------------------------
# Script
VERSION="1.0"							# Script version
LOG="/dev/tty"					    	# Default log to terminal

# Settings Receiver = Device
DEVICE_IP="xxx.xxx.xxx.xxx"           	# Device IP Address
DEVICE_TYPE="Undefined"             	# Device type read from device
DEVICE_STATUS="Undefined"           	# Device status read from device 
DEVICE_VOLUME_SCALE="Undefined"			# Volume scale [Relative/Abolute] <=== Only display value , value read will always be Relative
DEVICE_VOLUME_OFFSET=80					# Volume offset [dB to Abolute] 
DEVICE_XML=(
	'Deviceinfo.xml'
	'formMainZone_MainZoneXmlStatus.xml'
	'formMainZone_MainZoneXml.xml'
	'formNetAudio_StatusXml.xml'
)  										# Source types read from device
   
# Settings Domoticz
DOMO_IP="192.168.77.10"             	# Domoticz IP Address
DOMO_PORT="8080"                    	# Domoticz Port
DOMO_DEVICE_POWER_IDX="115"           	# On/Off    		(Switch) IDX
DOMO_DEVICE_POWER_STATUS_IDX="123"		# Status			(Switch) IDX slave (On/Off)
DOMO_DEVICE_VOL_ABS_IDX="122"        	# Absolute Volume 	(Slider) IDX


# ---------- Usage ---------------------------------------------------------------------
SCRIPT_USAGE()
{

    echo "usage: avreceiver.sh [-h] {-l]

This script will synchronize the status of a AV receiver (Denon / Marantz) with Domoticz.

Supported device types:
	DENON '*AVR-X1000'
	...  Additional models to be added/tested

Version:               $VERSION
Author:                BDV77

[-h]    = Help, display usage.
[-l]    = Log to file 'avreceiver.log' instead of terminal

Version history:
1.0	First release
0.1	Based on Denon script of Trixwood V0.3

to do: 	
	Get source input names from device
	Get custom source input names from device

"
}

# ---------- Read input arguments ---------------------------------------------------------------------
while [ "$1" != "" ]; do
    case $1 in
        -h | --help )           SCRIPT_USAGE
                                exit
                                ;;
        -l )					LOG="avreceiver.log"
                                ;;
        * )                     SCRIPT_USAGE
                                exit 1
    esac
    shift
done

# ---------- Functions ------------------------------------------------------------------------- 

# ---------- Main function --------------------------------------------------------------------- 
echo "$(date +%k:%M:%S.%N) Started avreceiver.sh" > $LOG


# Check if Domiticz status is online and service is running
PINGTIME=$(ping -c 1 -q "$DOMO_IP" | awk -F"/" '{print $5}' | xargs)
if ! expr $PINGTIME '>' 0 &> /dev/null ; then
	echo "Domoticz status = Offline [responsetime = $PINGTIME]" >> $LOG
	exit
fi
if [[ "$(curl -s "http://$DOMO_IP:$DOMO_PORT/json.htm?type=command&param=getversion" | grep "Domoticz")" == "" ]] ; then
	echo "Domoticz status = Onine but Domoticz service is not running" >> $LOG
	exit
fi
echo "Domoticz status = Online [responsetime = $PINGTIME] and Domoticz service is running" >> $LOG


# Check if device is online and verify identity
PINGTIME=$(ping -c 1 -q "$DEVICE_IP" | awk -F"/" '{print $5}' | xargs)
if ! expr PINGTIME '>' 0 &> /dev/null ; then
	echo "Device = Offline [responsetime = $PINGTIME]" >> $LOG
	# Set status to offline
	# Define default offline status in Domoticz
fi
echo "Device = Online [responsetime = $PINGTIME]" >> $LOG


# Get device type and try to identity
i=0
for XML in ${DEVICE_XML[@]}; do # Load device data
	XML_DATA[$i]="$(curl -s "http://$DEVICE_IP/goform/$XML")"
	i=$(($i+1))
done
DEVICE_TYPE=$(echo ${XML_DATA[0]} | grep -oPm1 "(?<=<ModelName>)[^<]+")
case $DEVICE_TYPE in
    "") #Nothing found --> not a AV receiver
		echo "No device type <ModelName> could be retreived from $DEVICE_IP/goform/Deviceinfo.xml" >> $LOG
		exit
        ;;
    "*AVR-X1000") #Add other device types that are identical
		echo Succesfully identified a supported device type: $DEVICE_TYPE >> $LOG
        ;;
#    "") #Add other device types here and define differences!
#        ...
#        ;;
    *) #Default to *AVR-X1000??
        echo "An unsupported device type <ModelName> was retreived from $DEVICE_IP/goform/Deviceinfo.xml = $DEVICE_TYPE, Default to *AVR-X1000"  >> $LOG
		DEVICE_TYPE="*AVR-X1000"
esac


# ---------- Update Power (via slave device) --------------------------------------------------------------------- 
POWER_STATUS=$(echo ${XML_DATA[1]} | grep -oPm1 "(?<=<Power><value>)[^<]+") #Read current values from xml data
POWER_STATUS="$(tr '[:lower:]' '[:upper:]' <<< ${POWER_STATUS:0:1})$(tr '[:upper:]' '[:lower:]' <<< ${POWER_STATUS:1})" # Convert to Capitalized, syntax from device is inconsistant

POWER_OLD=$(curl -s "http://$DOMO_IP:$DOMO_PORT/json.htm?type=devices&rid=$DOMO_DEVICE_POWER_IDX" | grep "Status" | cut -d'"' -f4 ) # Get old values from Domoticz

if [ "$POWER_STATUS" != "$POWER_OLD" ] ; then #Only update in case of difference
	curl -s -i -H "Accept: application/json" "http://$DOMO_IP:$DOMO_PORT/json.htm?type=command&param=switchlight&idx=$DOMO_DEVICE_POWER_STATUS_IDX&switchcmd=$POWER_STATUS" &> /dev/null
	echo "Domoticz Object: $DOMO_DEVICE_POWER_STATUS_IDX (POWER), updated to value = $POWER_STATUS" >> $LOG
else
	echo "Domoticz Object: $DOMO_DEVICE_POWER_STATUS_IDX (POWER) in sync, value = $POWER_STATUS" >> $LOG
fi


# ---------- Update Mute and Volume --------------------------------------------------------------------- 
DEVICE_MUTE=$(echo ${XML_DATA[1]} | grep -oPm1 "(?<=<Mute><value>)[^<]+");
DEVICE_MUTE="$(tr '[:lower:]' '[:upper:]' <<< ${DEVICE_MUTE:0:1})$(tr '[:upper:]' '[:lower:]' <<< ${DEVICE_MUTE:1})" # Convert to Capitalized, syntax from device is inconsistant
DEVICE_VOLUME_REL=$(echo ${XML_DATA[1]} | grep -oPm1 "(?<=<MasterVolume><value>)[^<]+") # Volume value always read relative from device
if [[ "$DEVICE_VOLUME_REL" == "--" ]]; then DEVICE_VOLUME_REL=$(echo "-$DEVICE_VOLUME_OFFSET" | bc) ; fi # Convert volume value in case "--"
DEVICE_VOLUME_ABS=$(echo "$DEVICE_VOLUME_OFFSET + "$DEVICE_VOLUME_REL"" | bc) # Calculate absolute volume value
DEVICE_VOLUME_ABS=$(printf "%.*f\n" 0 $DEVICE_VOLUME_ABS) # Round value, due to resolution of Domoticz slider
SLIDER_OLD=$(curl -s "http://$DOMO_IP:$DOMO_PORT/json.htm?type=devices&rid=$DOMO_DEVICE_VOL_ABS_IDX" | grep "Data" | cut -d'"' -f4 ); 
if 	[[ "$SLIDER_OLD" == "Off" ]]; then #Invert Off status of slider to Mute Status On
	MUTE_OLD="On"
else #Invert On status of slider to Mute Status Off
	MUTE_OLD="Off"
	if [[ "$SLIDER_OLD" != "On" ]]; then #if actual value is displayed, read value
		VOLUME_ABS_OLD=$(echo "$SLIDER_OLD" | grep -Eo '[0-9]{1,4}');
	fi
fi

if [[ "$DEVICE_MUTE" != "$MUTE_OLD" ]]; then #Only update in case of difference
	curl -s -i -H "Accept: application/json" "http://$DOMO_IP:$DOMO_PORT/json.htm?type=command&param=switchlight&idx=$DOMO_DEVICE_VOL_ABS_IDX&switchcmd=$MUTE_OLD" &> /dev/null
	echo "Domoticz Object: $DOMO_DEVICE_VOL_ABS_IDX (Mute), updated to value = $MUTE_OLD" >> $LOG
else
	echo "Domoticz Object: $DOMO_DEVICE_VOL_ABS_IDX (Mute) in sync, value = $MUTE_OLD" >> $LOG
fi
if [[ "$DEVICE_VOLUME_ABS" != "$VOLUME_ABS_OLD" ]] && [[ "$DEVICE_MUTE" == "Off" ]]; then #Only update in case of difference and Mute = Off
	curl -s -i -H "Accept: application/json" "http://$DOMO_IP:$DOMO_PORT/json.htm?type=command&param=switchlight&idx=$DOMO_DEVICE_VOL_ABS_IDX&switchcmd=Set%20Level&level=$(($DEVICE_VOLUME_ABS + 1))" &> /dev/null
	if [ "$DEVICE_VOLUME_ABS" = 0 ] ; then # If set to zero correct for auto switch to mute <=== THIS WILL SWICH EACH TIME BECAUSE VALUE ZERO WILL NOT BE DISPLAYED :(
		curl -s -i -H "Accept: application/json" "http://$DOMO_IP:$DOMO_PORT/json.htm?type=command&param=switchlight&idx=$DOMO_DEVICE_VOL_ABS_IDX&switchcmd=On" &> /dev/null
	fi
	echo "Domoticz Object: $DOMO_DEVICE_VOL_ABS_IDX (Volume), updated to value = $DEVICE_VOLUME_ABS" >> $LOG
else
	echo "Domoticz Object: $DOMO_DEVICE_VOL_ABS_IDX (Volume) in sync, value = $DEVICE_VOLUME_ABS" >> $LOG
fi

	
echo "$(date +%k:%M:%S.%N) Stoppped avreceiver.sh" >> $LOG

exit 0
