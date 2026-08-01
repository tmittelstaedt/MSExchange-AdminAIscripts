============================================================
README - Exchange Receive Connector Creation/Update Script
Version: 2.1
Author: Ted Mittelstaedt
============================================================

PURPOSE
-------
This PowerShell script creates or updates a secure Exchange
Receive Connector that allows anonymous SMTP relay from one
or more specific internal hosts.

It is designed to:
- Prevent open relay
- Allow only specified IP addresses to relay externally
- Automatically apply the correct relay permissions
- Work in both local and remote Exchange Management Shell

------------------------------------------------------------
FEATURES
------------------------------------------------------------
1. WARNING MESSAGE
   Displays a clear warning about proper usage before running.

2. USER INPUT
   Prompts for:
     - Connector name
     - One or more IP addresses (comma-separated)
   Uses the current server name automatically.

3. DNS VALIDATION
   For each IP entered:
     - Checks for a PTR (reverse DNS) record
     - Checks that the PTR hostname resolves in forward DNS
   If any IP fails, the script stops without making changes.

4. IP CONFLICT CHECK
   Ensures none of the entered IPs are already assigned to
   another Receive Connector on the same server.

5. CONNECTOR CREATION OR UPDATE
   - If the connector exists:
       Updates RemoteIPRanges, sets AnonymousUsers, and
       ensures TransportRole is FrontendTransport.
   - If the connector does not exist:
       Creates it with the specified settings.

6. RELAY PERMISSIONS
   Grants "NT AUTHORITY\ANONYMOUS LOGON" the right:
       Ms-Exch-SMTP-Accept-Any-Recipient
   This allows relay to external recipients from the
   specified IPs only.

7. REMOTE SESSION COMPATIBILITY
   Uses .Identity.ToString() for Set-ReceiveConnector to
   avoid parameter binding errors in remote PowerShell.

8. VERIFICATION
   Checks that the relay right is applied successfully.

9. SUMMARY OUTPUT
   Displays:
     - Connector name
     - Allowed IPs
     - Port
     - Server name

------------------------------------------------------------
REQUIREMENTS
------------------------------------------------------------
- Exchange Management Shell (local or remote)
- Exchange Organization Administrator rights
- PowerShell 5.1 or later
- DNS PTR and forward records for each IP

------------------------------------------------------------
USAGE
------------------------------------------------------------
1. Save the script as CreateOrUpdateReceiveConnector.ps1
2. Open Exchange Management Shell.
3. Run:
       .\CreateOrUpdateReceiveConnector.ps1
4. Follow the prompts.

------------------------------------------------------------
EXAMPLE
------------------------------------------------------------
Enter the name for the Receive Connector: RelayFromAppServer
Enter the internal host IP(s) allowed to relay (comma-separated if multiple): 192.168.1.50,192.168.1.51

------------------------------------------------------------
NOTES
------------------------------------------------------------
- This script is safe for production use if you only enter
  trusted internal IP addresses.
- Do NOT use this script to allow relay from "0.0.0.0/0" or
  any public IP range.
- Always verify relay functionality from the allowed IPs
  after running the script.

============================================================
END OF README
============================================================
5