# Generate self signed cert
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout mongodb.pem -out mongodb.pem -config openssl.cnf -extensions 'v3_req'

