def test_key_val_replacement_works(host):
    ''' Confirms addOrEditKeyValPair provides the expected output '''
    host.run('''
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "KEY_ONE" "value1" "./testoutput"
    addOrEditKeyValPair "KEY_TWO" "value2" "./testoutput"
    addOrEditKeyValPair "KEY_ONE" "value3" "./testoutput"
    addOrEditKeyValPair "KEY_FOUR" "value4" "./testoutput"
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE=value3\nKEY_TWO=value2\nKEY_FOUR=value4\n'
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
