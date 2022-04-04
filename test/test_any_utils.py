def test_key_val_replacement_works(host):
    ''' Confirms addOrEditKeyValPair provides the expected output '''
    host.run('''
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value1"
    addOrEditKeyValPair "./testoutput" "KEY_TWO" "value2"
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value3"
    addOrEditKeyValPair "./testoutput" "KEY_FOUR" "value4"
    addOrEditKeyValPair "./testoutput" "KEY_FIVE_NO_VALUE"
    addOrEditKeyValPair "./testoutput" "KEY_FIVE_NO_VALUE"
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE=value3\nKEY_TWO=value2\nKEY_FOUR=value4\nKEY_FIVE_NO_VALUE\n'
    assert expected_stdout == output.stdout


def test_key_val_removal_works(host):
    ''' Confirms removeKey provides the expected output '''
    host.run('''
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value1"
    addOrEditKeyValPair "./testoutput" "KEY_TWO" "value2"
    addOrEditKeyValPair "./testoutput" "KEY_THREE" "value3"
    removeKey "./testoutput" "KEY_TWO"
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE=value1\nKEY_THREE=value3\n'
    assert expected_stdout == output.stdout


def test_getFTLAPIPort_default(host):
    ''' Confirms getFTLAPIPort returns the default API port '''
    output = host.run('''
    source /opt/pihole/utils.sh
    getFTLAPIPort
    ''')
    expected_stdout = '4711\n'
    assert expected_stdout == output.stdout


def test_getFTLAPIPort_custom(host):
    ''' Confirms getFTLAPIPort returns a custom API port in a custom PORTFILE location '''
    host.run('''
    echo "PORTFILE=/tmp/port.file" > /etc/pihole/pihole-FTL.conf
    echo "1234" > /tmp/port.file
    ''')
    output = host.run('''
    source /opt/pihole/utils.sh
    getFTLAPIPort
    ''')
    expected_stdout = '1234\n'
    assert expected_stdout == output.stdout
