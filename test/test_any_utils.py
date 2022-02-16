def test_key_val_replacement_works(host):
    ''' Confirms addOrEditKeyValPair provides the expected output '''
    host.run('''
    setupvars=./testoutput
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "KEY_ONE" "value1" "./testoutput"
    addOrEditKeyValPair "KEY_TWO" "value2" "./testoutput"
    addOrEditKeyValPair "KEY_ONE" "value3" "./testoutput"
    addOrEditKeyValPair "KEY_FOUR" "value4" "./testoutput"
    cat ./testoutput
    ''')
    output = host.run('''
    cat ./testoutput
    ''')
    expected_stdout = 'KEY_ONE=value3\nKEY_TWO=value2\nKEY_FOUR=value4\n'
    assert expected_stdout == output.stdout
