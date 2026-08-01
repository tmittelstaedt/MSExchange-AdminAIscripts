# Exchange Receive Connector Creation/Update Script

**Version:** 2.1  
**Author:** (Your Name)  

---

## 📌 Purpose
This PowerShell script creates or updates a **secure Exchange Receive Connector** that allows anonymous SMTP relay from one or more specific internal hosts.

It is designed to:
- Prevent **open relay**
- Allow only **specified IP addresses** to relay externally
- Automatically apply the correct **relay permissions**
- Work in both **local and remote Exchange Management Shell**

---

## ✨ Features

1. **Warning Message**  
   Displays a clear warning about proper usage before running.

2. **User Input**  
   Prompts for:
   - Connector name
   - One or more IP addresses (comma-separated)  
   Uses the current server name automatically.

3. **DNS Validation**  
   For each IP entered:
   - Checks for a PTR (reverse DNS) record
   - Checks that the PTR hostname resolves in forward DNS  
   If any IP fails, the script stops without making changes.

4. **IP Conflict Check**  
   Ensures none of the entered IPs are already assigned to another Receive Connector on the same server.

5. **Connector Creation or Update**  
   - If the connector exists:
     - Updates `RemoteIPRanges`
     - Sets `AnonymousUsers`
     - Ensures `TransportRole` is `FrontendTransport`
   - If the connector does not exist:
     - Creates it with the specified settings

6. **Relay Permissions**  
   Grants `NT AUTHORITY\ANONYMOUS LOGON` the right:  
   `Ms-Exch-SMTP-Accept-Any-Recipient`  
   This allows relay to external recipients **only** from the specified IPs.

7. **Remote Session Compatibility**  
   Uses `.Identity.ToString()` for `Set-ReceiveConnector` to avoid parameter binding errors in remote PowerShell.

8. **Verification**  
   Checks that the relay right is applied successfully.

9. **Summary Output**  
   Displays:
   - Connector name
   - Allowed IPs
   - Port
   - Server name

---

## 🛠 Requirements
- Exchange Management Shell (local or remote)
- Exchange Organization Administrator rights
- PowerShell 5.1 or later
- DNS PTR and forward records for each IP

---

## 🚀 Usage
1. Save the script as `CreateOrUpdateReceiveConnector.ps1`
2. Open **Exchange Management Shell**
3. Run:
   ```powershell
   .\CreateOrUpdateReceiveConnector.ps1
