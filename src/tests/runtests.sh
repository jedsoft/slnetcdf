#!/bin/sh

ROOT="`pwd`/../.."

install_prefix=`slsh -n -e 'vmessage("%S",_slang_install_prefix)'`
scripts_dir="${install_prefix}/share/slsh/scripts"
run_test_pgm="slsh -n -g"
runprefix="$SLTEST_RUN_PREFIX"

use_slcov=0
while [ "$#" -ge 1 ]
do
  case "$1" in
    "--slcov" ) runsuffix="$scripts_dir/slcov"; shift
      rm -f test_*.slcov*
      use_slcov=1
      ;;
    "--sldb" ) runsuffix="$scripts_dir/sldb"; shift
      ;;
    "--stkchk" ) runsuffix="$scripts_dir/slstkchk"; shift
      ;;
    "--gdb" ) runprefix="gdb --args"; shift
      ;;
    "--memcheck" ) runprefix="valgrind --tool=memcheck --leak-check=yes --error-limit=no --num-callers=25"
      shift
      ;;
    "--strace" ) runprefix="strace -f -o strace.log"
      shift
      ;;
    * ) break
      ;;
  esac
done

########################################################################

if [ $# -eq 0 ]
then
    echo "Usage: $0 [--gdb|--sldb|--slcov|--stkchk|--strace|--memcheck] test1.sl test2.sl ..."
    exit 64
fi

echo
echo "Running module tests:"
echo

n_failed=0
tests_failed=""

for testxxx in $@
do
    echo $runprefix $run_test_pgm $runsuffix $testxxx
    $runprefix $run_test_pgm $runsuffix $testxxx

    if [ $? -ne 0 ]
    then
	n_failed=`expr $n_failed + 1`
	tests_failed="$tests_failed $testxxx"
    fi
done

echo
if [ $n_failed -eq 0 ]
then
    echo "All tests passed."
    if [ $use_slcov -eq 1 ]
    then
      lcov_merge_args=""
      for X in test_*.slcov*
      do
         lcov_merge_args="$lcov_merge_args -a $X"
      done
      lcov $lcov_merge_args -o "modules.slcov"
    fi
else
    echo "$n_failed tests failed: $tests_failed"
fi
echo

exit $n_failed
