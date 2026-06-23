# Sticker App 🎨 📱

Uma aplicação Flutter moderna e robusta para criação e gerenciamento de pacotes de figurinhas (stickers). Este projeto foi desenvolvido com foco em performance, escalabilidade e uma experiência de usuário fluida, utilizando as melhores práticas do ecossistema Flutter.

## 🚀 Funcionalidades

- **Gerenciamento de Pacotes**: Criação, edição e visualização de pacotes de figurinhas.
- **Editor de Figurinhas**: Ferramentas integradas para recortar e comprimir imagens.
- **Interface Intuitiva**: Design moderno seguindo as diretrizes do Material Design 3.
- **Navegação Declarativa**: Sistema de rotas robusto e escalável.
- **Gerenciamento de Estado**: Utilização eficiente do Riverpod para um estado reativo e testável.

## 🛠️ Tecnologias e Ferramentas

- **Linguagem**: [Dart](https://dart.dev/)
- **Framework**: [Flutter](https://flutter.dev/)
- **Gerenciamento de Estado**: [Riverpod](https://riverpod.dev/)
- **Navegação**: [GoRouter](https://pub.dev/packages/go_router)
- **Manipulação de Imagem**:
  - `image_picker` (Seleção de fotos)
  - `image_cropper` & `crop_your_image` (Recorte)
  - `flutter_image_compress` (Otimização)
- **Arquitetura**: Layered Architecture (Core, Modules, Shared)

## 🏗️ Arquitetura do Projeto

O projeto segue uma estrutura modular para facilitar a manutenção e escalabilidade:

```text
lib/
├── core/             # Configurações globais (Router, Theme, Utils)
├── modules/          # Funcionalidades específicas da aplicação
│   ├── packs/       # Gerenciamento de pacotes de figurinhas
│   └── stickers/    # Criação e edição de figurinhas individuais
└── shared/           # Componentes e serviços compartilhados
```

## 📦 Como Executar

### Pré-requisitos

- Flutter SDK instalado (versão compatível com o `pubspec.yaml`)
- Emulador Android/iOS ou dispositivo físico conectado

### Instalação

1. Clone o repositório:

   ```bash
   git clone https://github.com/seu-usuario/sticker.git
   ```

2. Instale as dependências:

   ```bash
   flutter pub get
   ```

3. Execute o projeto:

   ```bash
   flutter run
   ```

## 🧪 Testes

O projeto conta com uma base de testes unitários e de widgets para garantir a confiabilidade:

```bash
flutter test
```

```
