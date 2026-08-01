============================================================
TESTING EXCHANGE RECEIVE CONNECTOR USING TELNET (UBUNTU LINUX)
============================================================

PURPOSE
-------
This document explains how to test your Exchange Receive Connector
on port 25 using the telnet command from an Ubuntu Linux system.

It includes:
- Installing the telnet client on Ubuntu
- Connecting to the Exchange server on port 25
- Sending a test SMTP message manually
- Verifying relay permissions

------------------------------------------------------------
1. INSTALLING TELNET CLIENT ON UBUNTU
------------------------------------------------------------
By default, telnet is not installed on modern Ubuntu systems.

To install it, open a terminal and run:

    sudo apt update
    sudo apt install telnet

Verify installation:

    telnet --version

------------------------------------------------------------
2. CONNECTING TO THE EXCHANGE SERVER
------------------------------------------------------------
Syntax:

    telnet <ExchangeServerHostnameOrIP> 25

Example:

    telnet mailserver.example.com 25

Expected output:

    Trying 192.168.1.10...
    Connected to mailserver.example.com.
    Escape character is '^]'.
    220 mailserver.example.com Microsoft ESMTP MAIL Service ready

If you see "Connection refused" or "Unable to connect", check:
- Firewall rules
- Exchange Receive Connector bindings
- Network connectivity

------------------------------------------------------------
3. SENDING A TEST EMAIL VIA TELNET
------------------------------------------------------------
Once connected, type the following commands.
Press ENTER after each line.
Replace addresses and domain names with your own.

Example session:

    EHLO testclient.example.com
    MAIL FROM:<test@yourdomain.com>
    RCPT TO:<recipient@externaldomain.com>
    DATA
    Subject: Telnet Test Email

    This is a test email sent via telnet through the Exchange connector.
    .
    QUIT

NOTES:
- The period (.) on a line by itself ends the DATA section.
- If relay is not allowed for your IP, you may see:
      550 5.7.1 Unable to relay
      or
      550 5.7.54 SMTP; Unable to relay recipient in non-accepted domain
- If successful, you should see:
      250 2.6.0 <message-id> Queued mail for delivery
      or
      250 2.6.0 <5812f6bb-f71a-4faa-ad33-cba87f5da073@yourdomain.com> [InternalId=1743756722202, Hostname=testclient.example.com] 1537 bytes in 3.537, 0.424 KB/sec Queued mail for delivery
- After the QUIT you should see:
      221 2.0.0 Service closing transmission channel
------------------------------------------------------------
4. VERIFYING RELAY PERMISSIONS
------------------------------------------------------------
If you receive "Unable to relay", check:
- That your IP is listed in the connector's RemoteIPRanges
- That "AnonymousUsers" is enabled for the connector
- That "Ms-Exch-SMTP-Accept-Any-Recipient" permission is granted

------------------------------------------------------------
5. EXITING TELNET
------------------------------------------------------------
To exit telnet at any time:
- Press CTRL + ]
- Type: quit
- Press ENTER

------------------------------------------------------------
EXAMPLE FULL SESSION
------------------------------------------------------------
$ telnet mailserver.example.com 25
Trying 192.168.1.10...
Connected to mailserver.example.com.
Escape character is '^]'.
220 mailserver.example.com Microsoft ESMTP MAIL Service ready
EHLO testclient.example.com
250-mailserver.example.com Hello [192.168.1.50]
250-SIZE 37748736
250-PIPELINING
250-DSN
250-ENHANCEDSTATUSCODES
250-STARTTLS
250-X-ANONYMOUSTLS
250-AUTH LOGIN XOAUTH2
250-8BITMIME
250-BINARYMIME
250 CHUNKING
MAIL FROM:<test@yourdomain.com>
250 2.1.0 Sender OK
RCPT TO:<recipient@externaldomain.com>
250 2.1.5 Recipient OK
DATA
354 Start mail input; end with <CRLF>.<CRLF>
Subject: Telnet Test Email

This is a test email sent via telnet through the Exchange connector.
.
250 2.6.0 <message-id> Queued mail for delivery
QUIT
221 2.0.0 Service closing transmission channel
Connection closed by foreign host.

============================================================
END OF DOCUMENT
============================================================
