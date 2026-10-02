# Template de Relatório de Auditoria de Segurança

```markdown
# Relatório de Auditoria de Segurança — [Nome do Projeto]
Data: [AAAA-MM-DD] | Escopo: [Caminho do Projeto] | Framework: Flutter [Versão]

---

## 1. Sumário Executivo

- **Postura Geral:** [Resumo em 2-3 frases sobre o estado de segurança do projeto]
- **Total de Achados:**
  - 🔴 **CRITICAL:** [0]
  - 🟠 **HIGH:** [0]
  - 🟡 **MEDIUM:** [0]
  - 🟢 **LOW:** [0]
  - 🔵 **INFO:** [0]

---

## 2. Tabela de Vulnerabilidades

| ID | Severidade | Componente / Arquivo | Descrição Resumida |
|---|---|---|---|
| SEC-001 | CRITICAL / HIGH / ... | `lib/.../arquivo.dart` | Resumo da falha |

---

## 3. Detalhamento dos Achados

### [SEC-001] — [Título da Vulnerabilidade]
- **Severidade:** `CRITICAL` | `HIGH` | `MEDIUM` | `LOW` | `INFO`
- **Componente:** `lib/services/...`
- **Contexto & Descrição:** Explicação clara de como o problema ocorre e por que é um risco.
- **Evidência no Código:**
  ```dart
  // Trecho de código afetado
  ```
- **Impacto:** O que um atacante na mesma rede ou com acesso ao dispositivo pode fazer.
- **Recomendação & Mitigação:** Ação sugerida para sanar o problema.

---

## 4. Patches Sugeridos (Apenas Propostas para CRITICAL e HIGH)

```diff
- // Código antigo vulnerável
+ // Código novo protegido
```

---

## 5. Próximos Passos Recomendados
1. Ação imediata 1
2. Ação preventiva 2
```
