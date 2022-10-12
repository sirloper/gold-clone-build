#!/usr/bin/python3

import configparser, os
import smtplib
from email.MIMEMultipart import MIMEMultipart
from email.MIMEBase import MIMEBase
from email import Encoders
from os.path import basename
from email.mime.application import MIMEApplication
from email.mime.text import MIMEText
from email.utils import COMMASPACE, formatdate
import datetime

def send_mail(send_from, send_to, subject, text, files=None, server="127.0.0.1"):
	assert isinstance(send_to, list)
	msg = MIMEMultipart()
	msg['From'] = send_from
	msg['To'] = COMMASPACE.join(send_to)
	msg['Date'] = formatdate(localtime=True)
	msg['Subject'] = subject
	msg.attach(MIMEText(text))

	part = MIMEBase('application', "octet-stream")
	part.set_payload(open("/tmp/report.csv", "rb").read())
	Encoders.encode_base64(part)

	part.add_header('Content-Disposition', 'attachment; filename="report.csv"')

	msg.attach(part)

	smtp = smtplib.SMTP(server)
	smtp.sendmail(send_from, send_to, msg.as_string())
	smtp.close()
	
output = open( "/tmp/report.csv", 'w' )
output.write( "INI FILE,HOSTNAME,SERVICE NAME,CPU COUNT,MEMORY (GB),ESX HOST,CPU COUNT,MEMORY (KB)\n" )

files = os.listdir( '/var/www/cgi-bin/ini/' )
for file in files:
	filename, extension = os.path.splitext(file)
	extension.rstrip()
	if extension == '.ini':
			config = configparser.ConfigParser( strict=False )
			config.read( '/var/www/cgi-bin/ini/' + file )
			for server in config.sections():
				ram = int( config[server]["memory"] ) / 1024
				output.write( file + "," + server + "," + config[server]["service_name"] + "," + config[server]["cpus"] + "," + str( ram ) + "," + config[server]["vmhost"] + config[server]["cpus"] + "," + config[server]["memory"] + "\n" )
output.close() 

fromaddr = 'Clone_build_reporting'
toaddrs = ['mark.cartwright@cotiviti.com']
datestamp = datetime.date.today()
subject = "Clone build config report generated on " + str( datestamp )

send_mail( fromaddr, toaddrs, subject, subject, "/tmp/report.csv" )
