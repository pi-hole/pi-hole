def test_key_val_replacement_works(host):
    ''' Confirms addOrEditKeyValPair either adds or replaces a key value pair in a given file '''
    host.run('''
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value1"
    addOrEditKeyValPair "./testoutput" "KEY_TWO" "value2"
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value3"
    addOrEditKeyValPair "./testoutput" "KEY_FOUR" "value4"
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE=value3\nKEY_TWO=value2\nKEY_FOUR=value4\n'
    assert expected_stdout == output.stdout


def test_key_addition_works(host):
    ''' Confirms addKey adds a key (no value) to a file without duplicating it '''
    host.run('''
    source /opt/pihole/utils.sh
    addKey "./testoutput" "KEY_ONE"
    addKey "./testoutput" "KEY_ONE"
    addKey "./testoutput" "KEY_TWO"
    addKey "./testoutput" "KEY_TWO"
    addKey "./testoutput" "KEY_THREE"
    addKey "./testoutput" "KEY_THREE"
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE\nKEY_TWO\nKEY_THREE\n'
    assert expected_stdout == output.stdout


def test_key_removal_works(host):
    ''' Confirms removeKey removes a key or key/value pair '''
    host.run('''
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value1"
    addOrEditKeyValPair "./testoutput" "KEY_TWO" "value2"
    addOrEditKeyValPair "./testoutput" "KEY_THREE" "value3"
    addKey "./testoutput" "KEY_FOUR"
    removeKey "./testoutput" "KEY_TWO"
    removeKey "./testoutput" "KEY_FOUR"
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE=value1\nKEY_THREE=value3\n'
    assert expected_stdout == output.stdout


def test_getFTLAPIPortFile_default(host):
    ''' Confirms getFTLAPIPortFile returns the default API port file path '''
    output = host.run('''
    source /opt/pihole/utils.sh
    getFTLAPIPortFile
    ''')
    expected_stdout = '/run/pihole-FTL.port\n'
    assert expected_stdout == output.stdout


def test_getFTLAPIPort_default(host):
    ''' Confirms getFTLAPIPort returns the default API port '''
    output = host.run('''
    source /opt/pihole/utils.sh
    getFTLAPIPort "/run/pihole-FTL.port"
    ''')
    expected_stdout = '4711\n'
    assert expected_stdout == output.stdout


def test_getFTLAPIPortFile_and_getFTLAPIPort_custom(host):
    ''' Confirms getFTLAPIPort returns a custom API port in a custom PORTFILE location '''
    host.run('''
    tmpfile=$(mktemp)
    echo "PORTFILE=${tmpfile}" > /etc/pihole/pihole-FTL.conf
    echo "1234" > ${tmpfile}
    ''')
    output = host.run('''
    source /opt/pihole/utils.sh
    FTL_API_PORT_FILE=$(getFTLAPIPortFile)
    getFTLAPIPort "${FTL_API_PORT_FILE}"
    ''')
    expected_stdout = '1234\n'
    assert expected_stdout == output.stdout


def test_getFTLPIDFile_default(host):
    ''' Confirms getFTLPIDFile returns the default PID file path '''
    output = host.run('''
    source /opt/pihole/utils.sh
    getFTLPIDFile
    ''')
    expected_stdout = '/run/pihole-FTL.pid\n'
    assert expected_stdout == output.stdout


def test_getFTLPID_default(host):
    ''' Confirms getFTLPID returns the default value if FTL is not running '''
    output = host.run('''
    source /opt/pihole/utils.sh
    getFTLPID
    ''')
    expected_stdout = '-1\n'
    assert expected_stdout == output.stdout


def test_getFTLPIDFile_and_getFTLPID_custom(host):
    ''' Confirms getFTLPIDFile returns a custom PID file path '''
    host.run('''
    tmpfile=$(mktemp)
    echo "PIDFILE=${tmpfile}" > /etc/pihole/pihole-FTL.conf
    echo "1234" > ${tmpfile}
    ''')
    output = host.run('''
    source /opt/pihole/utils.sh
    FTL_PID_FILE=$(getFTLPIDFile)
    getFTLPID "${FTL_PID_FILE}"
    ''')
    expected_stdout = '1234\n'
    assert expected_stdout == output.stdout
