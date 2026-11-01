# Security

Report suspected vulnerabilities privately to admin@synapsea.agency. Do not
include live API keys, passports, bookings or other users' data in public issues.

Use a separate Vekha key per client, grant only the needed trips and capabilities,
and revoke access in Vekha when no longer needed. Do not paste a key into chat.
ChatGPT uses a separate OAuth grant approved inside Vekha.

The dependency-free stdio bridge connects only to the fixed Vekha HTTPS endpoint,
rejects redirects and does not execute document text, shell commands or file paths.
Its environment contains the key supplied by the client's sensitive setting.
The agent/host and its other tools may have different privileges: Vekha cannot
control what a human-authorized agent does with data it has already received.

Document text and links are untrusted input. Prompts in files cannot grant new
permissions. The MCP API excludes personal identity/insurance categories and
unshared participant documents; a permitted ticket can still contain names or
booking details. Never assume "travel document" means anonymous data.

No keys, production settings, databases or private repository history are part
of this distribution. No install hooks or auto-approval/trust bypasses are used.
Directory review and a public URL are not a guarantee that every client version
has passed end-to-end testing. Check the compatibility status in README.md.
