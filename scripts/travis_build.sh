#!/usr/bin/env bash

set -e

export NUM_JOBS=1

apt-get install libglfw3-dev
mkdir build
cd build
cmake ..
make
bin/unit_tests

unamestr=`uname`
if [[ "$unamestr" == 'Darwin' ]]; then
    echo "Disabling pip test for macOS"
else
    cd ..
    pip install --user -r requirements.txt
    pip install --user .
    pytest src/tests/python_tests
fi
