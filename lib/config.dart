/// Configuração global da app.
const String kAppName = 'PartilhaEcra';

/// Repositório GitHub onde são publicadas as versões (usado pelas atualizações).
const String kGithubRepo = 'opaxpk/PartilhaEcra';

/// Porta UDP usada para anunciar/descobrir dispositivos na rede local.
const int kDiscoveryPort = 45454;

/// Porta TCP (WebSocket) onde o Host aceita ligações de recetores.
const int kSignalPort = 45455;

/// Número máximo de recetores ligados ao mesmo tempo.
const int kMaxReceivers = 4;

/// Identificador do protocolo nos pacotes de descoberta.
const String kProtocolId = 'PartilhaEcra/1';
