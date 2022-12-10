@test "DNS server port is reported over Telnet API" {
  run bash -c 'echo ">dns-port >quit" | nc -v 127.0.0.1 4711'
  printf "%s\n" "${lines[@]}"
  [[ ${lines[1]} == "53" ]]
  [[ ${lines[2]} == "" ]]
}
