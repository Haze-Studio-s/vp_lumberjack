# vp_lumberjack (v3.1.0 - Audit Hardened)

Job de **lenhador de alto desempenho** para QBox / QBCore. Três sub-jobs imersivos com **física realista de queda**, **desdobro de toras**, **operação de garfo** (telehandler/empilhadeira), **controle de rampas de carreta**, **pagamento acumulado pago na devolução do veículo** e **cancelamento preventivo por morte / distância / dano**.

Server-authoritative, sem DB (estado volátil em runtime), **Dual-Asset Engine** (suporta assets customizados do `plt_lumberjack-streams` com fallback suave para nativos do GTA) e **interface padronizada com `lation_ui`** (com fallback automático para `ox_lib`).

Stack: `qbx_core` · `ox_lib` · `ox_inventory` · `ox_target` · `qbx_vehiclekeys` · `lation_ui` (opcional).
Segurança & Resmon: **Auditado e Hardened via Codex / GPT-5.5** (OmniRoute).

---

## 🌲 Visão Geral dos 3 Sub-Jobs

Fale com o **capataz** na serraria de Paleto Forest → menu interativo escolhe 1 dos 3 serviços.
Cada serviço **spawna o veículo apropriado**, entrega a chave e inicia o rastreio da sessão. O pagamento **acumula no servidor** e é creditado integralmente quando você **devolve o veículo** na zona demarcada da serraria.

| Serviço | Veículo Padrão | Fluxo Técnico e Operacional |
|---|---|---|
| **① Corte** | Telehandler (`jcb` / `forklift`) | Motosserra com som e partículas de serragem → árvore tomba com **física suave (28 passos)** → desdobro do tronco em toras no chão → **garfo do telehandler** carrega toras até o stand → devolve veículo. |
| **② Empilhamento** | Empilhadeira (`pltforklift` / `forklift`) | Pegar pallets com o garfo → acionar rampas do reboque → carregar e alinhar pallets na carreta → devolve veículo. |
| **③ Entrega** | Caminhão (`pltpacker` / `flatbed`) | Caminhão carregado com pallets → obra aleatória no mapa (**frete dinâmico por km rodado**) → descarregar pallets na zona demarcada → devolve veículo. |

> **Operação de Garfo (Resmon 0.00ms em repouso):** Aproxime o telehandler ou empilhadeira da zona verde; o sistema acorda dinamicamente, exibe TextUI e permite pressionar **[E]** para pegar; no destino, alinhe a direção e aperte **[E]** para soltar com som mecânico de trava.

---

## ⚡ Diferenciais de Engenharia da Versão 3.1.0

1. **Padrão Visual `lation_ui` Blindado:**
   - Camada bridge em `client/ui.lua` roteando notificações, TextUI, barras de progresso e menus de contexto no `lation_ui`.
   - Detecção síncrona de estado, tracking de provedor ativo (impede conflito com outros TextUIs) e timeout watchdog na barra de progresso contra telas travadas.
   - Limpeza mandatória de TextUI e entidades em `onResourceStop`.

2. **Blindagem Anti-Exploit Server-Authoritative:**
   - **Autorização em 2 Fases (Token + Duração Mínima):**
     * Corte: `beginFell` / `finishFell` com `fellMin`.
     * Entrega: `beginUnload` / `finishUnload` com `unloadMin`.
     * Empilhamento: `pickup` registra carga física e `drop` valida posse e tempo de transporte (`too_fast`).
   - **Fail-Closed de Veículos:** Todas as operações conferem a existência física e integridade do veículo de trabalho no servidor; qualquer remoção ou desvio encerra a sessão imediatamente sem pagamento.
   - **Locks de Spawn (`SpawnLocks`):** Eliminação de race condition em múltiplos spawns concorrentes no centro de trabalho.
   - **Watchdog Server-Side Autônomo:** O servidor checa independentemente a morte do ped, dano de motor/chassi e distância física, dispensando a confiança no cliente.
   - **Proteção Anti-Reentrância:** Encerramento e anulação do estado da sessão executados estritamente antes do disparo de pagamento na devolução.
   - **Teto Máximo de Ganhos:** Cap operacional por tipo de serviço evitando acúmulo desproporcional.

3. **Performance Cravada em 0.00ms (Resmon):**
   - Eliminação completa de loops `Wait(0)` a pé: loops de manobra só ativam 0ms se o jogador estiver efetivamente conduzindo o veículo de trabalho (`InForkVehicle()`).

4. **Física Realista de Queda e Partículas:**
   - Algoritmo de tombamento gradual com detecção de obstáculos e partículas de serragem (`ent_dst_wood_splinter`).
   - Desdobro do tronco caído via `ox_target`, gerando toras físicas para manobra com garfo.

5. **Logística de Carretas e Rampas:**
   - Rampas traseiras operáveis por `ox_target` (`Baixar / Subir Rampas da Carreta`) e som hidráulico.
   - Posicionamento tridimensional escalonado dos pallets na prancha.

6. **Dual-Asset Engine (Custom vs Nativo):**
   - Suporte transparente a assets customizados do `plt_lumberjack-streams` com fallback limpo para modelos nativos do GTA.

---

## 🛠️ Instalação e Configuração

### 1. Item no `ox_inventory` (Obrigatório)
Em `resources/[ox]/ox_inventory/data/items.lua`:
```lua
['chainsaw'] = {
    label = 'Motosserra',
    weight = 4500,
    stack = false,
    close = true,
    description = 'Ferramenta do lenhador. Necessária para derrubar árvores.',
},
```

### 2. Ativação no `server.cfg`
```cfg
ensure [standalone]
# ou individualmente:
ensure vp_lumberjack
setr ox:locale pt
```

### 3. Comandos Úteis
- `/serravolume 0-100` — Ajusta o volume do áudio da motosserra (salvo na sessão do jogador).

---

## 🛡️ Segurança e Server-Authoritative

- **Tokens de Ação:** O início do corte emite um token temporal que valida o tempo mínimo de serragem (`fellMin`), neutralizando injeção de triggers rápidos.
- **Validação Física de Distância:** Todas as entregas e descargas conferem a distância tridimensional no servidor (`Security.DistanceTo`).
- **Fail-Closed:** Acúmulo de pagamento em memória no servidor, liberado estritamente na devolução física do veículo de trabalho.

---

## 📁 Estrutura de Arquivos

```
config/
  config.lua         -- Configuração global, assets, economia e tempos
locales/
  pt.json            -- Localização completa em Português do Brasil
  en.json            -- Localização em Inglês
shared/
  utils.lua          -- Resolução dinâmica de assets (GetAsset), formatação
client/
  ui.lua             -- Bridge unificada lation_ui / ox_lib
  framework.lua      -- Gerenciamento de sessão, watchdog e cancelamento
  fork.lua           -- Operação de garfo com tick rate dinâmico
  cutting.lua        -- Física de queda, partículas e desdobro de toras
  stacking.lua       -- Empilhamento de pallets e rampas de carreta
  delivery.lua       -- Transporte e descarga nas obras
  polish.lua         -- Áudio e polimento da motosserra
  main.lua           -- NPC capataz e menu principal
server/
  security.lua       -- Auditoria de proximidade, tokens e anti-exploit
  framework.lua      -- Sessões de trabalho e liberação de pagamento
  cutting.lua        -- Estado autoritativo das árvores e toras
  stacking.lua       -- Controle de capacidade dos trailers
  delivery.lua       -- Geração de rotas e cálculo de frete por km
  main.lua           -- Eventos de cancelamento e concessão de ferramentas
```
