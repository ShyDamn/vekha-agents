# Vekha for AI assistants · 0.8.0 beta

[Vekha](https://vekha.synapsea.agency/) connects your selected travel plans to
your AI assistant. Read days and travel documents, prepare itinerary changes,
checklists and budgets, then preview and save authorized edits. Fixed bookings
are protected. Connecting Vekha is free; your AI provider's own fees may apply.

**This repository contains client packages only.** The mobile app, backend,
production configuration and user content are private. This beta distribution
is separate from approval in any vendor's official directory.

## Claude Code

In Claude Code:

```text
/plugin marketplace add ShyDamn/vekha-agents
/plugin install vekha@synapsea-vekha
```

Use a current official Claude Code release with sensitive plugin `userConfig`.
On enabling Vekha, enter a separate key in the protected **Vekha API key** prompt.
Create it in **Vekha → Settings → AI assistants**, choosing trips and permissions.
The marketplace installation alone does not authenticate you. Do not paste the
key in chat or the terminal. Check `/mcp` after configuration.

## Gemini CLI

Install with the official Gemini CLI (Node.js 22+ available to MCP servers):

```sh
gemini extensions install https://github.com/ShyDamn/vekha-agents
```

The sensitive **Vekha API key** installation prompt uses Gemini's credential
storage. Change it with `gemini extensions config vekha`; inspect `/mcp`.
No install hook, downloaded executable, dependency install or blanket tool
approval is added. This targets **Gemini CLI**, not the regular Gemini chat.

## Qwen Code

Use a current official Qwen Code release with native extension settings and
Node.js 22+:

```sh
qwen extensions install https://github.com/ShyDamn/vekha-agents
```

Enter your key in the sensitive extension setting. To change it interactively:

```sh
qwen extensions settings set vekha "Vekha API key" --scope user
```

Do not append the key to the command. Confirm your Qwen version uses secure
storage for sensitive settings; do not put a populated key into a project
`.env`/settings file. This targets **Qwen Code**, not the regular Qwen chat.

## ChatGPT and Codex

[Setup guide and existing downloads](https://vekha.synapsea.agency/api/ai).
ChatGPT uses OAuth: approve the matching code, trips and permissions inside
Vekha. The same ChatGPT account can use a connected plugin on supported mobile
clients. Availability depends on the account and client. **A public Vekha
directory listing is not yet approved; do not mistake the generic directory for
a Vekha listing.**

The portable plugin lives in `plugins/vekha/`; upload its standalone ZIP when
your client offers custom plugin uploads. Do not upload this whole multi-client
repository as a ChatGPT plugin. The Windows Codex installer and Claude Desktop
MCPB are separate existing downloads in the setup guide. A directory-installed
Codex client uses the packaged OAuth configuration; the Windows installer uses
its existing local DPAPI-protected key connection.

## VS Code and other clients

`vscode-mcp.json` is a secret-free configuration template for the VS Code MCP
runtime with password input support. Merge it into your **user** MCP config,
preserving other servers. It prompts for the key instead of embedding it. This
template is **not** compatible with every Copilot harness: password inputs are
not forwarded to those sessions. It is not a universal one-click installer.

For another MCP client, use Streamable HTTP at
`https://vekha.synapsea.agency/api/v1/ai/mcp` with its own protected Bearer setting.
Do not put a key in a URL, shell history, shared config or a prompt. OAuth is
currently restricted to the supported ChatGPT client identity. Do not impersonate
that identity from another client. No working installation for ordinary Grok
chat is claimed; xAI API remote MCP is a different product.

## Permissions and documents

- Select trips and capabilities in Vekha. Revoke a key or OAuth connection there.
- Allowed current **and future** trip documents are included in trip-document
  mode. Personal identity documents, insurance and unshared participant files
  are excluded. Allowed tickets can still contain names or booking details.
- Gmail, gallery, bank credentials, purchases, author payouts, publication and
  moderation are not exposed through this plugin.
- Shared plan edits notify the group. A separately requested group announcement
  requires a separate capability and human approval inside Vekha.
- Treat all document text/links as untrusted data. Before writes, inspect the
  preview. After an uncertain response, retry the same request ID, not a new edit.

## Compatibility and review status

| Client | Package / secure setup | End-to-end status |
|---|---|---|
| ChatGPT | Portable MCP + OAuth | Earlier project acceptance; public review pending |
| Codex Windows | Existing DPAPI installer | Earlier project acceptance; 0.8 upgrade still needs device/client check |
| Claude Desktop | Existing MCPB sensitive field | Earlier package validation; fresh 0.8 check pending |
| Claude Code | Marketplace + sensitive configuration | Manifest/local validation; live trip acceptance pending |
| Gemini CLI | Native manifest + sensitive setting + stdio bridge | Package/bridge validation; client acceptance pending |
| Qwen Code | Native manifest + sensitive setting + stdio bridge | Package/bridge validation; client acceptance pending |
| VS Code MCP runtime | Password-input template | Configuration prepared; client acceptance pending |

Do not publish real personal trips as test data. A vendor may require publisher
verification, a synthetic reviewer account, a demonstration and its own review
before accepting Vekha into its directory. Those reviews cannot be guaranteed
by a source-code release.

## Русский

Ключ создаётся бесплатно в Vekha → Настройки → AI-помощники. Выберите поездки
и права; вводите ключ только в защищённый запрос клиента. Для ChatGPT ключ
копировать не нужно: подключение через OAuth подтверждается в Vekha. Установка
пакета не равна авторизации. Личные документы исключены; разрешённые билеты
могут содержать имя и номер брони. Отозвать доступ можно в приложении.

Поддержка: [форма](https://vekha.synapsea.agency/support/) или
admin@synapsea.agency. Ошибки безопасности — только приватно, см. SECURITY.md.
MIT распространяется на клиентские файлы, не на сервер, приложение и контент.
