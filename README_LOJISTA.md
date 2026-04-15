# Neo B2-Plus: Relatório Técnico e Guia de Implantação (On-Premise)

Este documento atua como referência técnica para engenheiros, DevOps e arquitetos de software responsáveis pela implantação da arquitetura **Neo B2-Plus**. A solução opera em modelo "Self-Hosted" (On-Premise) focada em "Self-Custody" absoluto, desvinculando o fluxo de caixa de orquestradores centrais de terceiros.

---

## 1. Escopo de Arquitetura e Especificações Técnicas

O sistema é construído sobre linguagem Go (Backend/Gateway) e contratos inteligentes (Solidity, Rust, e TVM). 

### 1.1 Limitações Sistêmicas e Subsistemas Internos
Em virtude de mitigação contra vetores de ataque, a aplicação embute proteções hardcoded:
* **Rate Limiter:** Controle de tráfego de 10 requests por segundo, com capacidade de preempção (burst) de até 20 req/sec por endereço de IP (via Token Bucket).
* **Idempotency Engine:** Requisições via método HTTP `POST` impõem obrigatoriamente a presença do cabeçalho `Idempotency-Key`. As chamadas já efetuadas são retidas em memória (TTL) por 24 horas (`IdempotencyTTL = 24 * time.Hour`).
* **Preflight Validator:** Antes de emitir o payload criptográfico (EIP-712), a API mapeia ativamente o saldo (Balance) do usuário requerente. Transações não prosseguem se a soma de gás + token requerer mais ativos do que há na carteira (impedindo falhas e stress na rede).
* **Filtro On-Chain de Viabilidade:** O Indexador engloba um protetor estrito sob taxas de gas (`GasCostThreshold`). Transações cujo custo de execução transborde 10% do valor final (computado em USD com auxílio do oráculo) sofrerão *skip* imediato pelo gateway e não constarão como pagas.
* **Política Dinâmica de Confirmação de Blocos:** O algoritmo interno aguarda consolidação dependendo do risco monetário da transação antes de disparar o sucesso (evitando "Reorg Attacks"):
  * Faturas abaixo de `$100 USD`: Confirmação Rápida (5 Blocos).
  * Faturas de `$100 USD` até `$999 USD`: Confirmação Média (12 Blocos).
  * Faturas acima de `$1000 USD`: Segurança Máxima (32 Blocos).
* **Price Oracle (Auto-Update):** O núcleo da API aciona um *Worker* que requisita sincronização através da API da DeFiLlama a cada 5 minutos (`5*time.Minute`) garantindo paridade de preço para roteamento de tokens suportados e estimativa de taxas cruzadas no "Dynamic Routing Strategy".
* **RPC Failover Engine (Alta Disponibilidade):** O Módulo Go não depende de um único nó de Blockchain. O array `rpcUrls` recebe infraestruturas infinitas; se o nó primário (ex: Alchemy) cair, o sistema redireciona nativamente o tráfego em milissegundos para o nó secundário (ex: Infura), blindando o E-commerce contra apagões da rede.
* **Database Auto-Migration:** Dispensa uso de painéis dba ou injeção pesada de `SQL Dumps`. No startup, os objetos gorm (`User, Transaction, etc`) migram esquemas e colunas no PostgreSQL autonomamente.
* **Módulo Nativo de TLS:** Se instâncias x509 denominadas `server.crt` e `server.key` co-existirem na pasta raiz da aplicação (CWD), o binário automaticamente executa a elevação de protocolo `http://` para `https://` via rotina nativa `srv.ListenAndServeTLS`.

### 1.2 Restrições e Garantias On-Chain (Smart Contracts)
A arquitetura "Fábrica" contida nos binários compilados (Solidity/Solana/Tron) atua sob as seguintes premissas irrevogáveis de segurança e negócios:
* **Taxa de Roteamento Imutável (0.1%):** Conforme inspecionável em `SplitterLogic.sol`, a variável `FEE_BPS` está gravada com restritor lógico `constant = 10`. O frasco do contrato é imutável, o que significa que o mantenedor sistêmico jamais poderá aumentar a taxa descontada da sua venda de forma oculta.
* **Slippage BPS Control:** Transações processadas via Router de Troca (*PayWithSwap*) englobam por padrão uma derrapagem financeira (`DEFAULT_SLIPPAGE_BPS`) de `0.5%`. Faturas que sofrerem variações de liquidez acima disso entre a injeção e a execução vão estourar "Revert" (Rollback) impedindo prejuízo.
* **Eficiência EIP-1167 (Clone Factory):** Ao acionar o endpoint de "Onboarding", o Lojista não pagará o gás integral da compilação de contrato. A Fábrica forja Clones Minimalistas consumindo frações ínfimas de rede operando sobre uma Implementation primária e estática.
* **Timelock Rescue Bridge (Proteção de Fundos Travados):** Se criptomoedas forem acidentalmente enviadas pela rede para dentro do contrato do Lojista fora de uma transação validada, existe a função `rescueToken`. Contudo, ao solicitar o resgate (*proposeRescueToken*), a Blockchain emite um "Aviso Físico na Rede" e **congela o resgate por exatamente 2 Dias** (`TIMELOCK_DELAY = 2 days`). Isso garante ao Lojista uma resposta de emergência contra sequestros ou ataques internos na administração do Gateway.

### 1.3 Auditoria de Vulnerabilidades e Limitações Sistêmicas Adicionais (Disclaimer Crítico)
Após escrutínio arquitetônico na sub-camada de Solidity (`SplitterLogic.sol` e `MerchantFactory.sol`), alertamos as equipes integradoras sobre os seguintes cenários conhecidos:

* **Suporte Restrito de Roteamento Nativo no Swap Engine:**
  * O Gateway possui suporte brilhante a processamento nativo (Ethereum, BNB, Matic) nas rotas principais de repasse de valores ou cobrança direta (utilizando a flag `0x00...00` nas requisições). 
  * **A Limitação:** A única função do contrato blindada contra depósitos nativos é a `payWithSwap` (módulo DEX). O roteador de trocas funciona **estritamente invocando comandos IERC20**.
  * **O Contorno:** Se o seu cliente deseja pagar a fatura em outra moeda e instruir o contrato a fazer o intercâmbio (Swap) nativo em tempo real para a sua moeda preferida, obrigue a UI a empacotar o montante (utilizar a variante `WETH`, `WBNB`, etc) para rodar a engrenagem, evitando falhas transacionais pela rede.

* **Fator Spender Não-Blindado no Módulo de Swap:**
  * Embora restrito aos roteadores seguros (*AllowedRouters*), a função `payWithSwap` delega o comando do aprovador à variável inserida livremente pelo injetor da mensagem ("frontend"). Isso responsabiliza 100% o seu e-commerce a preencher corretamente as chaves do *Spender*, pois o protocolo Confia-No-Client. Desenvolva seu Frontend sem margens para Man-In-The-Middle no tráfego da variável.

---

## 2. Requisitos de Infraestrutura

**Servidor (Host):**
* **Sistema Operacional:** Distribuições baseadas em Debian/Ubuntu.
* **Go (Golang):** Versão mínima `>= 1.21` (necessário para scripts de build `deploy_all.sh`).
* **PostgreSQL:** RDBMS versão 14+ mandatória para mapeamento dos Indexadores e logs de Webhooks.

**Componentes Web3:**
* Acesso ativo a provedores de nós (RPCs) robustos.
* Node.js v18+ e frameworks locais (Hardhat para EVM, Anchor para Solana, TronBox para TVM) para o processo local de "Deploy".

---

## 3. Parametrização Inicial

Execute o utilitário nativo de build para instanciar as configurações matrizes do ambiente:

```bash
go run ./cmd/server --init
```

Esse comando injeta na raiz os arquivos base `config.json` e `.env`. 

### Parâmetros de Instância (`.env`)
Definição restrita de isolamento de chaves privadas sob arquitetura 12-Factor:
* `DATABASE_URL`: URI qualificada do PostgreSQL.
* `AUTHORIZER_PRIVATE_KEY`: A chave privada elíptica responsável por assinar todas as transações cruzadas no ecossistema de retaguarda (Backend-signing). Formato Hex com prefixo "0x".
* `MERCHANT_ADDRESS`: Endereço principal do Lojista. Parâmetro **vital de segurança** contra malwares e roubo de infraestrutura. 
  * **Como configurar:** Adicione a linha `MERCHANT_ADDRESS=0xSuaCarteiraOficialRecebedora` no seu `.env` e reinicie o servidor. Ao subir, o log do Terminal informará o `HWID` (Device ID) e criará uma fusão criptográfica entre seu CPU/OS e essa carteira. Se alguém roubar o código e rodar em outra máquina com IP diferente, o processador e o disco rígido diferirão, quebrando o hash imediatamente e paralisando a aplicação (Proteção Anti-Clone).
* `ADMIN_API_KEY`: Padrão simétrico para travar instâncias de API administrativas (`MIDDLEWARE.AdminAuthMiddleware`).
* `WEBHOOK_SECRET`: Cadeia persistente que será utilizada para computação "HMAC-SHA256" no fechamento da transação (Validação Endpoint a Endpoint).
* `DISCORD_WEBHOOK_URL`: Alarme de telemetria para *circuit breaking* e falhas graves no nó RPC local.

### Mapeamento de Redes (`config.json`)
O array `networks` deve ser estritamente preenchido com:
* `type`: Suporta os valores `evm`, `solana`, `tron`.
* `networkId`: Parâmetro inteiro para correspondência exata da rede subjacente.
* `rpcUrls`: Recomendado ao menos dois endpoints distintos por objeto para instanciar o "RPC Failover Engine".
* `allowedOrigins`: Uma propriedade estrita para injetar Cross-Origin Resource Sharing (CORS). Certifique-se de listar a URL exata do seu front-end pra liberar ordens emitidas direto pelo navegador.
* `factoryAddress`: Preenchido estritamente após a etapa de deploy explicada a seguir.

---

## 4. O "Deploy" dos Contratos (Ato Exclusivo e Obrigatório do Lojista)

> ⚠️ ATENÇÃO EXTREMA: Sendo este um gateway verdadeiramente Descentralizado e "Self-Hosted", o protocolo **NÃO** distribui os seus cartórios digitais automaticamente. É **OBRIGAÇÃO TOTAL** e inalienável da sua equipe técnica implantar os contratos nas respectivas Blockchains, usando os cofres da conta gerencial de vocês! Se não houver deployment, o `Backend` rejeitará a inicialização logo de cara.

A infraestrutura demanda um deploy das fábricas primárias (`MerchantFactory`) nas redes que pretende operar.

**Exemplo Prático (Deploy EVM - Polygon/BSC):**
1. Acesse o terminal raiz e instale as dependências via pacote `npm install`.
2. Garanta de exportar as diretrizes de rede necessárias presentes nos sub-arquivos de `scripts/deploy_evm.js`.
3. Inicie o compilador e injetor:
```bash
npx hardhat run scripts/deploy_evm.js --network polygon
```
4. Salve o contrato mestre exposto via STDOUT e retro-alimente o arquivo `config.json` na propriedade `factoryAddress` atrelada à Polygon. 
*Repita o processo para as ramificações `deploy_tron.sh` e `deploy_solana.sh` para escalonamento cross-chain.*

---

## 5. Gateway API: Referência Técnica

Instância unificada consumida no porto definido (padrão `:8080/api/v1`).

### Endpoints de Leitura Padrão
* `GET /health` : Serviço de diagnóstico contínuo de nó e conectividade.
* `GET /config` : Distribuição de variáveis restritas ("feeBps", "chainId" disponíveis) provendo o frontend ativamente sem "hardcoding" cliente.
* `GET /status/:id` : Retorna a persistência imutável da transação contida pelo ID interno. Status mapeados: `pending`, `processing`, `completed`, `failed`.

### Endpoints Transacionais (Exige `X-API-Key`)
* `POST /pay` : Estabelece as regras de envio da fatura de transação e instaura validação P2P preflight.
  * O retorno consiste das propriedades `tx_hash`, `gas_limit`, `expiry`, integrando o fluxo EIP-712.
* `PATCH /pay/:payment_id/hash` : Notificação imposta via formulário assíncrono para vincular e acionar verificação contra o Mempool das redes RPCs após a assinatura final do Web3 na tela cliente.

### Endpoints Administrativos Internos
* `POST /onboard-merchant` : Comando interserviço para expansão da fábrica gerando EIP-1167 Clones de franqueados (útil em contexto de Multi-Vendedores).
* `GET /payments/:payment_id/verify` : Subverte a dependência assíncrona do Indexador primário forçando o motor de escalonamento a revisar o bloco local, ideal se logs de sincronia caírem momentaneamente sob Reorg Networks.

---

## 6. Frontend Binding e Checkout Técnico

O binário expõe de modo estático elementos UI fundamentais através do path `/ui`. Contudo, para intersecção remota, o integrador web deve considerar os seguintes vetores cruciais em Javascript nativo.

Na eventualidade do acionamento de rede não-nativa do usuário (Exemplo: transacionar em BSC Network `56` quando a MetaMask encontra-se no Ethereum Padrão), instiga-se o método de troca RPC `wallet_switchEthereumChain`:

```javascript
// Exemplo em requisição para BNB BSC (NetworkID = 56 = 0x38 Hex)
try {
  await window.ethereum.request({
    method: 'wallet_switchEthereumChain',
    params: [{ chainId: '0x38' }],
  });
} catch (switchError) {
   // Integrar wallet_addEthereumChain em cenários falhos
}

// Injeção de EIP-712 com o Payload retornado do /api/v1/pay
const txHash = await window.ethereum.request({
  method: 'eth_sendTransaction',
  params: [{
    to: payload.to,
    data: payload.data,
    gas: payload.gas_limit
  }]
});
```

A finalização exige roteamento estrito contra o `PATCH /pay/:payment_id/hash` carregando o `txHash` computado para a ativação do indexador no Backend.

---

## 7. Protocolo de Encerramento (Webhooks e Retry Policy)

O Backend emitirá sinal PUSH via POST ao endereço registrado pelo comerciante sempre que a imutabilidade for confirmada. O fluxo impõe **Exponential Backoff Engine**: Em caso de falha intermitente na API do lojista (Rate limit ou indisponibilidade local server), o Dispatcher re-agendará o ping em saltos exponenciais (`~2m, ~4m, ~8m`) acrescidos de *Network Jitter* anti-DDoS, limitando-se a um teto de 5 tentativas.

### Formato de Saída (JSON Payload)
```json
{
  "event": "payment.success",
  "payment_id": "8fa8cc1b2390f...",
  "network": "bsc",
  "tx_hash": "0x4ca112b32948c...",
  "amount_paid": "45.00",
  "currency": "USDT",
  "timestamp": 1715481600
}
```

O integrador de infraestrutura final fica expressamente instruído a interceptar e invocar verificação criptográfica sobre o cabeçalho repassado: `X-Gateway-Signature`. O processamento consiste em aplicar `HMAC-SHA256` sobre o payload total utilizando o `WEBHOOK_SECRET` idêntico à configuração primária (`.env`). Validações omissas comprometem rigorosamente a segurança física do sistema contra ataques "replay".
