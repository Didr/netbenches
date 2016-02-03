#!/bin/sh
# This script prepare the result from bench-lab.sh to be used by ministat and/or gnuplot
# 
set -eu

# An usefull function (from: http://code.google.com/p/sh-die/)
die() { echo -n "EXIT: " >&2; echo "$@" >&2; exit 1; }

data_2_ministat () {
	# Convert raw data file from bench-lab.sh for list
	# $1 : Input file
	# $2 : Prefix of the output file
	local LINES=`wc -l $1`
	LINES=`echo ${LINES} | cut -d ' ' -f1`
	# Remove the first 15 lines (garbage or not good result) and the 10 last lines (bad result too)
	CLEAN_ONE=`mktemp /tmp/clean.1.data.XXXXXX` || die "can't create /tmp/clean.1.data.xxxx"
	head -n `expr ${LINES} - 10` $1 | tail -n `expr ${LINES} - 10 - 15` > ${CLEAN_ONE}
	# Filter the output (still filtering "0 pps" lines in case of) and kept only the numbers:
	# example of good line:
	# 290.703575 main_thread [1441] 729113 pps (730571 pkts in 1002000 usec)
	CLEAN_TWO=`mktemp /tmp/clean.2.data.XXXXXX` || die "can't create /tmp/clean.2.data.xxxx"
	grep -E 'main_thread[[:space:]]\[[[:digit:]]+\][[:space:]][1-9].*pps' ${CLEAN_ONE} | cut -d ' ' -f 4 > ${CLEAN_TWO}
	#Now we calculate the median value of this run with ministat
	echo `ministat -n ${CLEAN_TWO} | tail -n -1 | tr -s ' ' | cut -d ' ' -f 5` >> ${LAB_RESULTS}/$2
	rm ${CLEAN_ONE} ${CLEAN_TWO} || die "ERROR: can't delete clean.X.data.xxx"
	return 0
}

data_2_gnuplot () {
	# Now we will generate .dat file with name like: forwarding.dat
	# and contents like:
	# revision  pps
	# this file can be used for gnuplot
	if [ -n "${CFG_LIST}" ]; then
		# For each CFG detected previously
		for CFG_TYPE in ${CFG_LIST}; do
			echo "# (revision)	median	minimum		maximum" > ${LAB_RESULTS}/${CFG_TYPE}.data
			# For each file regarding the CFG (one file by revision)
			# But don't forget to exclude the allready existing CFG_TYPE.plot file from the result
			for DATA in `ls -1 ${LAB_RESULTS} | grep "[[:punct:]]${CFG_TYPE}$"`; do
				local REV=`basename ${DATA}`
				REV=`echo ${REV} | cut -d '.' -f 1`
				if [ ${REV} = "none" ]; then
				# Get the median, minimum and maximum value regarding all test iteration
					ministat -n ${LAB_RESULTS}/${DATA} | tail -n -1 | awk '{print $5 " " $3 " " $4}' >> ${LAB_RESULTS}/${CFG_TYPE}.data
				#echo "${REV}	${PPS}" >> ${LAB_RESULTS}/${CFG_TYPE}.data
				else
					ministat -n ${LAB_RESULTS}/${DATA} | tail -n -1 | awk -vrev=${REV} '{print rev " " $5 " " $3 " " $4}' >> ${LAB_RESULTS}/${CFG_TYPE}.data
				fi
			done
		done	
	else
		echo "TODO: plot.dat when different configuration sets are not used"	
	fi
	# Merge all .data file into one gnuplot.data
	[ -f ${LAB_RESULTS}/gnuplot.data ] && mv ${LAB_RESULTS}/gnuplot.data ${LAB_RESULTS}/gnuplot.bak
 	for DATA in `ls -1 ${LAB_RESULTS}/*.data`; do
        local FILENAME=`basename ${DATA}`
        local KEY=${FILENAME%.data}
		[ ! -f ${LAB_RESULTS}/gnuplot.data ] && echo "#key median minimum maximum" > ${LAB_RESULTS}/gnuplot.data
        echo -n "${KEY} " >> ${LAB_RESULTS}/gnuplot.data
		grep -v '#' ${DATA} >> ${LAB_RESULTS}/gnuplot.data
    done

	return 0
}

## main

SVN=''
CFG=''
CFG_LIST=''

[ $# -ne 1 ] && die "usage: $0 benchs-directory"
[ -d $1 ] || die "usage: $0 benchs-directory"

LAB_RESULTS="$1"
# Info: /tmp/benchs/bench.1.1.4.receiver

INFO_LIST=`ls -1 ${LAB_RESULTS}/*.info`
[ -z "${INFO_LIST}" ] && die "ERROR: No report files found in ${LAB_RESULTS}"

echo "Summaring results..."
for INFO in ${INFO_LIST}; do
	# Get svn rev number
	#  Image: /tmp/BSDRP-244900-upgrade-amd64-serial.img
	#  Image: /monpool/benchs-images/BSDRP-244900-upgrade-amd64-serial.img.xz
	#  => 244900 
	SVN=`grep 'Image: ' ${INFO} | cut -d ':' -f 2`
	# =>  /monpool/benchs-images/BSDRP-244900-upgrade-amd64-serial.img.xz
	SVN=`basename ${SVN} | cut -d '-' -f 2`
	# => 244900
	# Get CFG file name
	#  CFG: /tmp/bench-configs/forwarding
	#  => forwarding
	if grep -q 'CFG: ' ${INFO}; then
		CFG=`grep 'CFG: ' ${INFO} | sed 's/CFG: //g'`
		CFG=`basename ${CFG}`
		MINISTAT_FILE="${SVN}.${CFG}"
		# If not already, add the configuration type to the list of detected configuration
		echo ${CFG_LIST} | grep -w -q ${CFG} || CFG_LIST="${CFG_LIST} ${CFG}"
	else
		MINISTAT_FILE="${SVN}"
	fi
	# Now need to generate ministat input file for each different REPORT
	#   if report is: /tmp/benchs/bench.1.1.info
	#   => list all file like /tmp/benchs/bench.1.1.*.receiver
	DATA_LIST=`echo ${INFO} | sed 's/info/*/g'`
	DATA_LIST=`ls -1 ${DATA_LIST} | grep receiver`
	# clean allready existing ministat
	[ -f ${LAB_RESULTS}/${MINISTAT_FILE} ] && rm ${LAB_RESULTS}/${MINISTAT_FILE}
	for DATA in ${DATA_LIST}; do
		data_2_ministat ${DATA} ${MINISTAT_FILE}
	done # for DATA
done # for REPORT
echo "Gnuplot input data file generation..."
data_2_gnuplot

echo "Done"
exit
