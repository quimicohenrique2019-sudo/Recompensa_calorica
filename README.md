# GameFit

Aplicativo Flutter para Android que registra treinos, calcula pontos pelo tempo
de atividade e lê frequência cardíaca de relógios Bluetooth Low Energy (BLE)
compatíveis com o perfil padrão de frequência cardíaca (GATT `180D` / `2A37`).

## Pontuação

Cada minuto de treino registrado vale 10 pontos. A pontuação da sessão em
andamento aparece no painel e é somada ao total do dia ao finalizar o treino.
Pontos, minutos e treinos concluídos ficam salvos localmente por dia. Nesta
versão inicial, o tempo é iniciado e encerrado manualmente; frequência cardíaca
é exibida quando chega do relógio e não altera a pontuação.

## Executar no Android

Instale o Flutter SDK e o Android SDK, depois:

```sh
flutter create --platforms=android .
flutter pub get
flutter run
```

O Android solicita permissões de Bluetooth para procurar e conectar dispositivos.
O relógio deve estar próximo e transmitir o perfil Bluetooth padrão de frequência
cardíaca. Relógios que sincronizam exclusivamente por aplicativos ou protocolos
proprietários não são descobertos por esta integração BLE genérica.
