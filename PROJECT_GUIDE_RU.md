# DragonStride: путеводитель по проекту и архитектуре

Этот документ предназначен для разработчика, который впервые открыл проект. Он описывает не только целевую архитектуру из `AGENTS.md`, но и фактически реализованное поведение текущего кода.

Актуальность описания: состояние рабочей копии на 14 июля 2026 года. Проект использует Godot 4.6 и GDScript.

## 1. Что это за проект

DragonStride сейчас представляет собой двухмерную игру на клеточной карте. Игрок управляет персонажем, перемещается по проходимым клеткам, атакует соседние клетки, сущности и объекты. Игра поддерживает одиночный режим и Steam-мультиплеер с лобби. Дополнительно существует включаемый через консоль пошаговый режим, в котором игроки и мир действуют по очереди.

Общая игровая оболочка — `scenes/world/match_world.tscn`, а `scenes/full_world/full_world.tscn` является одним конкретным уровнем. Меню, сессия, сетевое соединение и жизненный цикл матча находятся вне данных карты.

## 2. Короткая ментальная модель

Если запомнить только пять понятий, пусть это будут они:

1. `GameSession` знает, какой режим запущен, кто участвует и какой уровень выбран.
2. `WorldLevel` хранит состав конкретной карты: тайлы, размещённые объекты, точки появления и визуальные узлы.
3. `MatchController` запускает и завершает матч.
4. `WorldRuntime` — единый типизированный вход из gameplay-кода в возможности мира.
5. Профильные `World*`-сервисы выполняют конкретную работу: сетка, регистрация, бой, ходы, создание объектов, сеть и реакции AI.

Упрощённая формула взаимодействия:

```text
ввод игрока → Entity / CharacterModel → WorldRuntime → профильный World-сервис
                                                    ↓
                                            изменение мира
                                                    ↓
                                      View / HUD и, при необходимости, сеть
```

## 3. Основные возможности проекта на данный момент

### 3.1. Запуск приложения и меню

- Приложение стартует со сцены главного меню `scenes/menu/main_menu/main_menu.tscn`.
- Из главного меню можно запустить одиночную игру, перейти в Steam-лобби, открыть настройки или выйти.
- Экран настроек позволяет выбрать одно из пяти разрешений окна и центрирует окно на экране.
- Кнопка завершения в игровом HUD заканчивает матч и возвращает в главное меню.

### 3.2. Игровая сессия

- Поддерживаются состояния: сессии нет, одиночная игра, multiplayer-host и multiplayer-client.
- В сессии хранятся выбранный `level_id`, lobby ID, Steam ID хоста и локального игрока, список игроков и настройки матча.
- Для одиночной игры создаётся один локальный игрок `Patrick`.
- Для мультиплеера список игроков строится по участникам Steam-лобби.
- Уровень выбирается по разрешённому `level_id`; каталог содержит `full_world` и тестовый `level_1`.

### 3.3. Steam-лобби

- Инициализация Steam и relay network.
- Создание публичного лобби максимум на четыре участника.
- Поиск только ожидающих лобби DragonStride.
- Вход и выход из лобби.
- Отображение состава лобби, владельца и локального пользователя.
- Запуск матча владельцем лобби.
- Координация старта host/client через сообщения Steam lobby chat.

### 3.4. Сетевой transport

- Создание `SteamMultiplayerPeer` для host и client.
- Сопоставление Godot `peer_id` со Steam ID.
- Передача состояния персонажей, атак, движения NPC, здоровья, смерти/возрождения, состояний AI и объектов.
- Синхронизация пошагового состояния.
- Сетевое создание разрешённых сущностей и объектов.
- Кэширование состояний объектов, AI и созданных во время матча объектов для подключающихся участников.
- Разделение часто обновляемого состояния персонажа (`unreliable`) и одноразовых игровых событий (`reliable`).

### 3.5. Уровень и жизненный цикл матча

- Конкретный уровень задаёт размер сетки, имена проходимых TileMap-слоёв и точки появления игроков.
- `MatchController` настраивает runtime, запускает матч после готовности дерева сцены, включает музыку и завершает матч.
- При завершении матча останавливается музыка, проигрывается звук смерти, закрывается активная multiplayer-сессия, очищается `GameSession` и открывается главное меню.

### 3.6. Клеточная сетка

- Размер клетки — 64 пикселя.
- Размер сетки текущего уровня по умолчанию — 18 × 18 клеток.
- Поддерживается преобразование координат мира в координаты клетки и обратно.
- Проверяются границы сетки.
- Проходимость определяется наличием тайла в разрешённом слое; сейчас основной проходимый слой — `Ground`.
- Можно получить центр текущей или соседней клетки.

### 3.7. Регистрация, занятость и резервирование клеток

- Объекты и сущности регистрируются по стабильным ID.
- Реестр хранит занятые объектами клетки.
- Реестр хранит текущие клетки сущностей.
- На время движения целевая клетка резервируется, чтобы две сущности не вошли в неё одновременно.
- Поддерживаются сущности и объекты, занимающие несколько клеток.
- Проверка размещения сообщает, находится ли клетка вне сетки, непроходима, занята объектом/сущностью или зарезервирована.
- По клетке можно найти сущность, объект или человекочитаемое имя поверхности.

### 3.8. Игроки и камера

- Игроки создаются сервисом `WorldPlayers` из одной сцены персонажа.
- Одиночный игрок получает фиолетовый вариант воина.
- Multiplayer-игроки получают цвета Blue, Purple, Red и Yellow по порядку.
- Для локального игрока создаётся камера.
- Камера умеет плавно следовать за игроком и переключаться в свободный режим с перемещением у краёв экрана.
- Multiplayer authority узлов игроков назначается после построения Steam ID ↔ peer ID mapping.

### 3.9. Управление персонажем и движение

- Перемещение выполняется клавишами WASD по четырём ортогональным направлениям.
- Режим атаки включается клавишей Q или кнопкой с мечом; это режим по умолчанию.
- Режим взаимодействия включается клавишей E или кнопкой с открытой рукой.
- Курсор локального игрока показывает текущий режим над миром и HUD: `tool_sword_a.svg` для атаки и `hand_open.svg` для взаимодействия. При выходе из матча возвращается системный курсор.
- Сущность проверяет состояние, правила текущего хода и доступность целевой клетки.
- Перед анимацией перемещения клетка резервируется.
- Перемещение визуально выполняется Tween-анимацией.
- После завершения обновляются занятость клеток, состояние хода и реакции AI.
- При удерживании клавиши персонаж продолжает движение, пока это разрешено.
- Во время открытой консоли ввод перемещения и атаки блокируется.

### 3.10. Бой, здоровье, смерть и возрождение

- Атака выполняется левой кнопкой мыши по соседней ортогональной клетке.
- Сначала проигрывается анимация атаки, затем применяется игровой результат.
- Если на клетке находится сущность, ей наносится урон атакующего.
- Если сущности нет, но есть `GridObject`, объект переводится в уничтоженное состояние.
- Результаты атак выводятся в игровую консоль.
- Каждая сущность получает визуальную полоску здоровья.
- Обычная NPC-сущность при нулевом здоровье удаляется.
- Игрок при нулевом здоровье сразу возрождается на своей стартовой клетке с полным здоровьем.
- У сетевых клиентов синхронизируются здоровье, удаление NPC и возрождение игрока.

### 3.11. Пошаговый режим

- По умолчанию режим выключен: игра допускает свободное движение и атаки.
- Включение и выключение выполняется консольными командами `game_turns_enable` и `game_turns_disable`.
- Состояния режима: ход игрока и ход мира.
- За ход игрок получает до 10 шагов и одну результативную атаку по сущности или объекту.
- Пустая атака не расходует доступную атаку.
- Игрок может завершить ход пробелом; если анимация ещё идёт, завершение откладывается.
- Игроки ходят в порядке, построенном из `GameSession`.
- Отключённый или отсутствующий multiplayer-игрок пропускается.
- После всех игроков начинается ход мира.
- Во время хода мира запускается `behavior()` доступных `NonPlayerEntity`.
- После завершения действий всех мировых сущностей начинается новый раунд.
- Host хранит авторитетное состояние ходов и рассылает снимки клиентам.

### 3.12. NPC и AI

- `NonPlayerEntity` задаёт общий контракт поведения NPC.
- Овца во время хода мира пытается двигаться в текущем горизонтальном направлении; при блокировке разворачивается.
- Вражеский воин имеет состояния `passive` и `active`.
- Воин активируется, когда живой персонаж оказывается в соседней клетке, включая диагональ.
- Активный воин сохраняет ID цели.
- Для поиска пути к клетке атаки используется обход в ширину по четырём направлениям.
- Воин учитывает границы, проходимость, объекты и, при реальном движении, текущую занятость клеток.
- За мировой ход воин делает максимум три шага и одну атаку.
- Воин возвращается в пассивное состояние, если цель исчезла, побеждена или недостижима.
- В multiplayer решения AI принимает host; клиенты воспроизводят очередь удалённых движений и атак.
- `WorldAwareness` повторно проверяет триггеры AI при регистрации и перемещении персонажей.

### 3.13. Создание сущностей и объектов в runtime

- Консольная команда `game_create <type> <x> <y>` создаёт разрешённый тип в указанной клетке.
- Каталог содержит `sheep`, `warrior`, `tree`, `house`, `meat`, `precision_stone` и `meteor_scroll`.
- До создания проверяются границы, проходимость, занятость и резервации.
- Созданным экземплярам назначается уникальный `spawn_id`.
- В multiplayer клиент отправляет запрос, host выполняет проверку и рассылает результат.
- Список созданных объектов кэшируется для поздно подключившихся клиентов.

### 3.14. Объекты мира

- Базовый `GridObject` имеет ID, список занимаемых смещений и состояния `NORMAL`/`DESTROYED`.
- Дерево занимает одну клетку.
- Дом занимает квадрат 2 × 2 клетки.
- Разрушение сейчас бинарное: первая успешная атака меняет состояние и текстуру.
- Уничтоженный объект не удаляется из реестра и продолжает занимать клетки.

### 3.15. Визуализация и вспомогательный UI

- Отрисовка сетки только над проходимыми клетками.
- Включение и выключение линий сетки через консоль.
- Подсветка клетки под курсором, если она проходима или содержит объект/сущность.
- Отдельные view-компоненты управляют спрайтами, направлением и анимациями игрока, овцы и воина.
- HUD содержит кнопку завершения игры, пять обычных слотов, кнопки атаки/взаимодействия с SVG-иконками, пять слотов заклинаний и корзину.
- Локальные gameplay-сообщения выводятся через `ConsoleOutput` в подключённый console addon.

### 3.16. Заклинания и свиток метеорита

- `WorldSpells` владеет выбором заклинания, проверкой каста, лимитами применений и созданием временных визуальных эффектов.
- Обычные предметы и заклинания хранятся в двух независимых контейнерах по пять слотов. Прототип с `inventory_kind = "spell"` не может попасть в обычный слот.
- Свиток `meteor_scroll` содержит заклинание `meteor`, остаётся в инвентаре после применения и не складывается в стек: каждый экземпляр занимает отдельный spell-слот.
- В пошаговом режиме каждый занятый spell-слот даёт одно независимое применение за ход. Индикатор `остаток/всего` конкретного слота отображается в его правом верхнем углу.
- В свободном режиме свиток можно использовать повторно без расходования; один игрок не может запустить второй метеорит до завершения первого.
- Во время полёта и взрыва метеорита двигаться могут все игроки, кроме персонажа, который в данный момент находится в целевой клетке эффекта.
- Метеорит летит к центру выбранной клетки детерминированным `Tween`. Завершение движения является моментом удара; физические коллизии не используются.
- При ударе host заново определяет содержимое клетки, наносит сущности 50 урона либо повреждает `GridObject` через `WorldCombat`.
- `NetworkSpellChannel` принимает от клиента только индекс spell-слота и клетку. Host определяет заклинание по своему inventory snapshot и рассылает авторитетное событие каста до запуска локального VFX.
- Узел канала называется `Spells`; его имя и путь в `network_manager.tscn` являются частью версии сетевого протокола.

## 4. Общая блок-схема проекта

Сплошная стрелка означает прямой вызов или владение. Пунктирная — событие, сигнал или сетевую передачу.

```mermaid
flowchart TB
    subgraph Application["Приложение и навигация"]
        MainMenu["MainMenu"]
        Settings["Settings"]
        LobbyUI["Lobby UI"]
        HUD["HUD"]
    end

    subgraph Global["Глобальные Autoload"]
        GameSession["GameSession\nрежим, игроки, выбранный уровень"]
        SteamManager["SteamManager\nлобби Steam"]
        NetworkManager["NetworkManager\npeer mapping, RPC, transport"]
        Console["Console addon"]
        GodotSteam["GodotSteam addon / Steam API"]
    end

    subgraph Match["Матч и конкретный уровень"]
        WorldLevel["WorldLevel\nданные карты и корни сцены"]
        MatchController["MatchController\nlifecycle матча"]
        WorldRuntime["WorldRuntime\nтипизированный фасад"]

        subgraph Services["Инкапсулированные World-сервисы"]
            WorldGrid["WorldGrid\nкоординаты и проходимость"]
            WorldRegistry["WorldRegistry\nID, занятость, резервации"]
            WorldPlayers["WorldPlayers\nигроки и камера"]
            WorldCombat["WorldCombat\nатаки и урон"]
            WorldTurns["WorldTurns\nраунды и допустимость действий"]
            WorldSpawner["WorldSpawner\nпроверка и создание"]
            WorldAwareness["WorldAwareness\nреакции NPC на персонажей"]
            WorldNetwork["WorldNetwork\nадаптер домена к сети"]
        end
    end

    subgraph Domain["Игровой домен"]
        CharacterModel["CharacterModel\nввод"]
        PlayerCharacter["PlayerCharacter"]
        NPC["NonPlayerEntity\nSheep / Warrior"]
        Objects["GridObject\nTree / House"]
        Views["Views / HealthBar"]
        Camera["Camera"]
        GridUI["GridLines / CellHover"]
    end

    MainMenu --> GameSession
    LobbyUI --> SteamManager
    SteamManager --> GameSession
    SteamManager --> NetworkManager
    SteamManager --> GodotSteam
    GameSession -->|"загрузка выбранной сцены"| WorldLevel
    HUD -. "end_game" .-> MatchController
    MatchController --> WorldRuntime
    MatchController --> GameSession
    WorldLevel --> MatchController
    WorldLevel --> WorldRuntime
    WorldLevel --> Services

    WorldRuntime --> WorldGrid
    WorldRuntime --> WorldRegistry
    WorldRuntime --> WorldPlayers
    WorldRuntime --> WorldCombat
    WorldRuntime --> WorldTurns
    WorldRuntime --> WorldSpawner
    WorldRuntime --> WorldAwareness
    WorldRuntime --> WorldNetwork

    CharacterModel --> PlayerCharacter
    PlayerCharacter --> WorldRuntime
    NPC --> WorldRuntime
    Objects --> WorldRuntime
    WorldPlayers --> PlayerCharacter
    WorldPlayers --> Camera
    WorldSpawner --> NPC
    WorldSpawner --> Objects
    WorldTurns -->|"behavior во время хода мира"| NPC
    WorldAwareness -->|"consider_character_trigger"| NPC
    PlayerCharacter --> Views
    NPC --> Views
    GridUI --> WorldRuntime
    WorldRuntime --> Console

    WorldNetwork --> NetworkManager
    NetworkManager -. "RPC reliable / unreliable" .-> NetworkManager
    NetworkManager -->|"SteamMultiplayerPeer"| GodotSteam
```

Последняя петля `NetworkManager → NetworkManager` обозначает обмен между экземплярами этого autoload на разных компьютерах, а не рекурсивный локальный вызов.

## 5. Как запускается матч

```mermaid
sequenceDiagram
    actor User as Пользователь
    participant Menu as MainMenu или Lobby
    participant Session as GameSession
    participant Net as NetworkManager
    participant Level as WorldLevel
    participant Match as MatchController
    participant Runtime as WorldRuntime
    participant Registry as WorldRegistry
    participant Players as WorldPlayers

    User->>Menu: Начать игру
    alt Одиночная игра
        Menu->>Net: stop_network()
        Menu->>Session: start_singleplayer()
    else Steam-мультиплеер
        Menu->>Session: start_multiplayer_from_lobby()
        Menu->>Net: start_from_session()
        Net-->>Menu: network_started
    end
    Menu->>Session: go_to_selected_scene()
    Session->>Match: Загружается match_world.tscn
    Match->>Level: Создаётся сцена выбранного level_id
    Match->>Runtime: configure_for_level(level)
    Runtime->>Registry: collect_blockers()
    Runtime->>Players: prepare_players_root()
    Runtime->>Players: start_singleplayer() / start_multiplayer()
    Runtime->>Registry: зарегистрировать игроков и NPC уровня
    Match->>Runtime: connect_signals()
    Match->>Match: включить музыку
```

Практически вся подготовка игрового мира начинается в `WorldRuntime.start_game()`, но вызывается владельцем lifecycle — `MatchController`.

## 6. Как проходит действие игрока

### 6.1. Движение

```mermaid
sequenceDiagram
    actor User as Игрок
    participant Model as CharacterModel
    participant Entity as PlayerCharacter / Entity
    participant Runtime as WorldRuntime
    participant Turns as WorldTurns
    participant Registry as WorldRegistry
    participant Network as WorldNetwork
    participant Awareness as WorldAwareness

    User->>Model: WASD
    Model->>Entity: request_move(direction)
    Entity->>Turns: can_entity_move_in_turn(entity)
    Turns-->>Entity: разрешено / запрещено
    Entity->>Registry: can_enter_cell(target)
    Entity->>Registry: reserve_entity_cell(target)
    Entity->>Network: broadcast_entity_move_started(...)
    Entity->>Entity: Tween до центра клетки
    Entity->>Registry: complete_entity_move(...)
    Entity->>Turns: notify_entity_moved(...)
    Registry-->>Awareness: через Runtime — персонаж изменился
    Awareness-->>Entity: NPC проверяют триггеры персонажа
```

### 6.2. Атака

```mermaid
sequenceDiagram
    actor User as Игрок
    participant Model as CharacterModel
    participant Entity as PlayerCharacter
    participant Turns as WorldTurns
    participant Combat as WorldCombat
    participant Registry as WorldRegistry
    participant Target as Entity или GridObject
    participant Net as WorldNetwork / NetworkManager

    User->>Model: ЛКМ по клетке
    Model->>Entity: request_attack_cell(cell)
    Entity->>Turns: can_entity_attack_in_turn(...)
    Entity->>Entity: проиграть анимацию атаки
    Entity->>Turns: notify_entity_attacked(...)
    Entity->>Combat: apply_attack_to_cell(...)
    Combat->>Registry: найти сущность или объект
    alt Сущность
        Combat->>Target: take_damage(damage)
        Combat->>Net: результат, health, respawn или remove
    else Объект
        Combat->>Target: take_damage() → DESTROYED
        Combat->>Net: object_state
    else Пустая клетка
        Combat->>Combat: только сообщение в консоль
    end
    Entity->>Turns: notify_entity_action_finished(...)
```

## 7. Машина состояний пошагового режима

```mermaid
stateDiagram-v2
    [*] --> Disabled
    Disabled --> PlayerTurn: game_turns_enable
    PlayerTurn --> PlayerTurn: следующий доступный игрок
    PlayerTurn --> WorldTurn: все игроки завершили ход
    WorldTurn --> WorldTurn: NPC выполняют behavior
    WorldTurn --> PlayerTurn: все NPC завершили действие, новый раунд
    PlayerTurn --> Disabled: game_turns_disable
    WorldTurn --> Disabled: game_turns_disable
```

В `PlayerTurn` активен один игрок, у которого есть 10 шагов и одна результативная атака. В `WorldTurn` игроки не управляют персонажами, а host или одиночная игра запускает поведение всех доступных NPC.

## 8. Сетевой путь атаки: роль host и фактический поток

```mermaid
sequenceDiagram
    participant ClientModel as CharacterModel клиента
    participant ClientWN as WorldNetwork клиента
    participant ClientNM as NetworkCombatChannel клиента
    participant HostNM as NetworkCombatChannel host
    participant HostWN as WorldNetwork host
    participant HostCombat as WorldCombat host
    participant Clients as WorldNetwork клиентов

    ClientModel->>ClientWN: request_character_attack(cell)
    ClientWN->>ClientNM: request_attack(cell)
    ClientNM->>HostNM: _submit_attack(cell) — reliable intent
    HostNM-->>HostWN: attack_requested(cell, requester_peer_id)
    HostWN->>HostWN: определить игрока по peer, проверить соседство и ход
    HostWN->>HostNM: broadcast_entity_attack(entity_id, cell)
    HostNM-->>Clients: authority RPC
    Clients->>Clients: запустить принятую анимацию атаки
    HostWN->>HostWN: запустить локальную анимацию после broadcast
    HostWN->>HostCombat: применить авторитетный результат
    HostCombat->>HostNM: broadcast result / health / respawn / remove
    HostNM-->>Clients: authority state
```

Клиентский attack intent содержит только целевую клетку. Host сам определяет персонажа по зарегистрированному `requester_peer_id`; клиентская анимация начинается только после получения `entity_attack` от host. Для взаимодействий сначала отправляется `interaction` intent и только затем host применяет действие. Для заклинаний host рассылает принятый cast result до запуска VFX. Один и тот же порядок «сеть, затем визуал» применяется также к авторитетным атакам NPC.

Для непрерывного положения персонажей используется другой путь: клиент отправляет `character_state` в режиме `unreliable`, host проверяет соответствие отправителя Steam ID и допустимость синхронизации в текущем ходу, затем ретранслирует состояние.

## 9. Иерархия игровых типов

```mermaid
flowchart TB
    Entity["Entity\nпозиция, клетка, здоровье, движение, атака"]
    Player["PlayerCharacter\nsteam_id, локальный ввод, respawn"]
    NPC["NonPlayerEntity\nобщий behavior-контракт"]
    Sheep["Sheep\nнейтральное движение"]
    Warrior["Warrior\nпоиск цели, путь и атака"]
    CharacterModel["CharacterModel\nчитает клавиатуру и мышь"]
    CharacterView["CharacterView\nспрайт и анимации игрока"]
    NonPlayerView["NonPlayerView\nвизуальный контракт NPC"]
    SheepView["SheepView"]
    WarriorView["WarriorView"]
    HealthBar["HealthBar"]

    GridObject["GridObject\nID, занимаемые клетки, состояние"]
    Tree["Tree\n1 клетка"]
    House["House\n2 × 2 клетки"]

    Entity --> Player
    Entity --> NPC
    NPC --> Sheep
    NPC --> Warrior
    Player --> CharacterModel
    Player --> CharacterView
    NPC --> NonPlayerView
    NonPlayerView --> SheepView
    NonPlayerView --> WarriorView
    Entity --> HealthBar
    GridObject --> Tree
    GridObject --> House
```

Стрелка на этой схеме читается как «базовый блок → специализация или принадлежащий компонент».

## 10. Все основные инкапсулированные блоки

### 10.1. Приложение, сессия и transport

| Блок | Где находится | Что инкапсулирует |
|---|---|---|
| `MainMenu` | `scenes/menu/main_menu/` | Навигацию из главного меню, запуск одиночной сессии и переход к lobby/settings. |
| `Settings` | `scenes/menu/settings/` | Выбор разрешения, оконный режим и центрирование окна. |
| `LobbyMain` | `scenes/menu/lobby/lobby_main.gd` | Выбор между созданием и поиском Steam-лобби. |
| `LobbyHost` | `scenes/menu/lobby/lobby_host.gd` | Экран состава лобби, host-controls и запуск игры владельцем. Этим же экраном пользуется вошедший клиент. |
| `LobbyJoin` | `scenes/menu/lobby/lobby_join.gd` | Запрос списка лобби, отображение результатов и подключение. |
| `GameSession` | `scenes/multiplayer/game_session.gd` | Режим игры, выбранную сцену, игроков, Steam IDs и настройки матча. Не хранит правила мира. |
| `SteamManager` | `scenes/multiplayer/steam_manager.gd` | Внешний Steam lobby API, relay readiness, участников и координацию старта матча. |
| `NetworkManager` | `scenes/multiplayer/network_manager.gd` | Низкоуровневый peer transport, mapping, RPC, delivery mode и сетевые кэши. Это единственное место для `@rpc`, `rpc()` и `rpc_id()`. |
| `Console` addon | `addons/console/` | Внешнюю игровую консоль и регистрацию команд. Это сторонний код; без отдельной задачи его не изменяют. |
| `ConsoleOutput` | `scenes/console/console_output.gd` | Маленькую границу между gameplay-сообщениями и внешним console addon. |

### 10.2. Уровень, lifecycle и runtime

| Блок | Где находится | Что инкапсулирует |
|---|---|---|
| `WorldLevel` | `scenes/world/world_level.gd` | Данные конкретной карты и типизированный доступ к корням/узлам уровня. |
| `match_world.tscn` | `scenes/world/match_world.tscn` | Общую оболочку матча: сервисы, runtime, controller, Players, audio, HUD и контейнер выбранного уровня. |
| `full_world.tscn` | `scenes/full_world/full_world.tscn` | Конкретную карту: Water/Ground/Clouds и размещённые House/Tree/Sheep/Warrior без общей инфраструктуры. |
| `MatchController` | `scenes/world/match_controller.gd` | Загрузку выбранного уровня, запуск/завершение матча, runtime-signals, музыку и переход в меню. |
| `WorldRuntime` | `scenes/world/world_runtime.gd` | Устойчивый API мира для сущностей и компонентов. Связывает загруженный уровень с общими сервисами. |
| `WorldGrid` | `scenes/world/services/world_grid.gd` | Размер и координаты сетки, границы, размер клетки и проходимые TileMap-слои. |
| `WorldRegistry` | `scenes/world/services/world_registry.gd` | ID, регистрацию, занятые и зарезервированные клетки, поиск сущностей/объектов и проверку размещения. |
| `WorldPlayers` | `scenes/world/services/world_players.gd` | Создание игроков, spawn cells, цвета, локального игрока, камеру и multiplayer authority. |
| `WorldCombat` | `scenes/world/services/world_combat.gd` | Выбор цели в клетке, применение урона, повреждение объектов и формирование результата боя. |
| `WorldTurns` | `scenes/world/services/world_turns.gd` | Состояние раунда/хода, порядок игроков, лимиты действий, мировой ход и сетевые snapshots. |
| `WorldSpawner` | `scenes/world/services/world_spawner.gd` | Каталог разрешённых типов, проверку размещения, создание, ID и сетевую репликацию runtime-spawn. |
| `WorldSpells` | `scenes/world/services/world_spells.gd` | Выбор и применение заклинаний, лимиты свитков за ход и orchestration временных spell-эффектов. |
| `WorldAwareness` | `scenes/world/services/world_awareness.gd` | Уведомление NPC о появлении и изменении положения персонажей; решения конкретного AI остаются в NPC. |
| `WorldNetwork` | `scenes/world/services/world_network.gd` | Перевод сетевых сигналов в операции текущего уровня и доменных событий в вызовы `NetworkManager`. |

### 10.3. Сущности, модели и представления

| Блок | Где находится | Что инкапсулирует |
|---|---|---|
| `Entity` | `scenes/entities/entity/entity.gd` | Общие характеристики сущности: ID, имя, тип, health/damage, клетку, движение, атаку, смерть и health bar. |
| `PlayerCharacter` | `scenes/entities/character/character.gd` | Состояние игрока, Steam ID, remote state, цвет, анимацию атаки и особое возрождение вместо удаления. |
| `CharacterModel` | `scenes/entities/character/character_model.gd` | Пользовательский ввод, продолжение движения, отправку сетевого состояния и запрос завершения хода. |
| `CharacterView` | `scenes/entities/character/character_view.gd` | Цветной спрайт игрока, направление взгляда и анимации idle/walk/attack. |
| `NonPlayerEntity` | `scenes/entities/non_player_entity/non_player_entity.gd` | Общий gameplay-контракт NPC, behavior, remote move/attack и уведомление о завершении действия. |
| `NonPlayerView` | `scenes/entities/non_player_entity/non_player_view.gd` | Общий визуальный контракт NPC без игровых решений. |
| `Sheep` | `scenes/entities/sheep/sheep.gd` | Нейтральную NPC с 25 HP и простым горизонтальным поведением. |
| `SheepView` | `scenes/entities/sheep/sheep_view.gd` | Спрайт овцы, направление и idle/walk-анимации. |
| `Warrior` | `scenes/entities/enemies/warrior/warrior.gd` | Вражеский AI, цель, BFS-путь, лимиты мирового хода, атаку и воспроизведение сетевых действий. |
| `WarriorView` | `scenes/entities/enemies/warrior/warrior_view.gd` | Направление, idle/run/guard и двухчастную анимацию атаки воина. |
| `HealthBar` | `scenes/entities/health_bar/health_bar.tscn` | Визуальную полоску здоровья, автоматически добавляемую каждой `Entity`. |

### 10.4. Объекты и визуальные компоненты мира

| Блок | Где находится | Что инкапсулирует |
|---|---|---|
| `GridObject` | `scenes/objects/grid_object/grid_object.gd` | Общий контракт статического клеточного объекта: ID, occupied offsets, normal/destroyed state и текстуры. |
| `Tree` | `scenes/objects/tree/` | Одноклеточную специализацию `GridObject`. |
| `House` | `scenes/objects/house/` | Специализацию `GridObject`, занимающую четыре клетки 2 × 2. |
| `Camera` | `scenes/camera/` | Follow/free режимы камеры и консольные команды переключения. |
| `GridLines` | `scenes/grid_lines/` | Отрисовку границ проходимых клеток и команды show/hide. |
| `CellHover` | `scenes/cell_hover/` | Подсветку доступной для взаимодействия клетки под мышью. |
| `HUD` | `scenes/hud/` | Ввод интерфейса матча; сейчас только сигнал запроса завершения игры. |

## 11. Кто какими данными владеет

| Данные | Владелец | Почему именно он |
|---|---|---|
| Режим, выбранный уровень, список игроков | `GameSession` | Эти данные живут дольше одной сцены уровня и описывают сессию. |
| Тайлы, spawn cells, визуальные узлы карты | `WorldLevel` / `.tscn` | Это содержание конкретного уровня. |
| Ссылки на сервисы текущего уровня | `WorldRuntime` | Он является общей точкой доступа к runtime-возможностям. |
| Размер клетки, границы, проходимость | `WorldGrid` | Это единая предметная область сетки. |
| ID и занятость клеток | `WorldRegistry` | Один источник истины предотвращает конфликты движения и размещения. |
| Раунд, активный игрок, шаги и атаки | `WorldTurns` | Это состояние пошаговых правил. |
| Health, damage, текущая клетка конкретной сущности | `Entity` | Это собственное игровое состояние сущности. |
| Состояние passive/active и цель воина | `Warrior` | Это специализированное поведение конкретного AI. |
| Normal/destroyed конкретного объекта | `GridObject` | Это собственное состояние объекта. |
| Steam lobby state | `SteamManager` | Это граница внешнего Steam API. |
| Peer mapping, RPC и сетевые кэши | `NetworkManager` | Это transport-уровень, общий между сценами. |
| Применение сетевого события к узлам уровня | `WorldNetwork` | Только этот адаптер одновременно знает домен уровня и сигналы transport. |

## 12. Карта каталогов

```text
project.godot                  настройки проекта, autoload и Input Map
AGENTS.md                      обязательные архитектурные правила разработки
PROJECT_GUIDE_RU.md            этот вводный документ

scenes/
  menu/                        главное меню, настройки, Steam lobby UI
  multiplayer/                 GameSession, SteamManager, NetworkManager
  world/                       общая оболочка матча, runtime, lifecycle и World-сервисы
  full_world/                  сцена и конфигурация уровня full_world
  levels/                      дополнительные сцены и конфигурации уровней
  entities/
    entity/                    базовая Entity
    character/                 игрок: model + view + scene
    non_player_entity/         базовые контракты NPC и NPC-view
    sheep/                     нейтральная овца
    enemies/warrior/           вражеский воин и AI
    health_bar/                визуальное здоровье
  objects/
    grid_object/               базовый объект сетки
    tree/                      дерево
    house/                     дом
  camera/                      камера локального игрока
  grid_lines/                  визуальные линии клеток
  cell_hover/                  подсветка клетки
  hud/                         HUD матча
  console/                     адаптер вывода в консоль

addons/console/                внешний console addon
addons/godotsteam/             внешняя интеграция GodotSteam
art/                           графические ресурсы Tiny Swords
fonts/                         шрифты и лицензии
```

`.godot/` — генерируемый кэш редактора. Его не следует читать как исходный код, редактировать или включать в ручные изменения.

## 13. Где искать код для типичных задач

| Если нужно изменить… | Начать с | Затем проверить |
|---|---|---|
| Размер сетки или проходимость | `WorldLevel`, `WorldGrid` | TileMap-слои конкретного `.tscn`. |
| Занятость клеток | `WorldRegistry` | `Entity.occupied_offsets`, `GridObject.occupied_offsets`. |
| Правила перемещения | `Entity`, `WorldTurns` | `WorldRegistry.can_enter_cell()`, network replay. |
| Управление игроком | `CharacterModel` | `PlayerCharacter` и Input Map в `project.godot`. |
| Урон и выбор цели | `WorldCombat` | `Entity.take_damage()`, `GridObject.take_damage()`, `WorldNetwork`. |
| Раунды и лимиты действий | `WorldTurns` | `NetworkManager` turn RPC и NPC `behavior()`. |
| Поведение конкретного NPC | Скрипт NPC, например `warrior.gd` | `NonPlayerEntity`, `WorldAwareness`, `WorldTurns`. |
| Создание нового runtime-объекта | `WorldSpawner.CATALOG` | Новая scene, базовый `Entity` или `GridObject`, network cache. |
| Создание нового уровня | Новый `WorldLevel`-совместимый `.tscn`, level-скрипт и `LevelDefinition.tres` | Каталог `GameSession`; Runtime/Controller/сервисы предоставляет общий `match_world.tscn`. |
| Lobby | `SteamManager` и `scenes/menu/lobby/` | `GameSession.start_multiplayer_from_lobby()`. |
| RPC или delivery mode | `NetworkManager` | Доменное применение события в `WorldNetwork`. |
| Анимацию игрока | `CharacterView` и `character.tscn` | Не переносить туда combat/turn/network rules. |
| Анимацию NPC | Конкретный view | Базовый контракт `NonPlayerView`. |
| Завершение матча | `MatchController` | HUD-сигнал и сетевой end-game flow. |
| Игровое сообщение | `ConsoleOutput` | Не отправлять текст локального лога по сети. |

## 14. Архитектурные границы, которые нельзя нарушать

### `WorldLevel` — карта, а не приложение

Не помещайте в корневой скрипт уровня запуск сессии, правила боя, AI, transport или переходы меню. Уровень должен оставаться заменяемым набором данных и узлов.

### `MatchController` — только lifecycle

Он может начать и закончить матч, управлять связанными с lifecycle эффектами и переходом сцены. Он не должен вычислять проходимость, урон, AI или занятость клеток.

### `WorldRuntime` — фасад, а не склад всей логики

Сущности обращаются к миру через него, но реализация остаётся в профильных сервисах. Новая операция добавляется в runtime только если это устойчивая возможность мира, нужная потребителям.

### Gameplay не должен владеть transport

RPC размещаются в `NetworkManager`. `WorldNetwork` адаптирует сетевые события к объектам уровня. Entity, View, HUD и GridObject не должны напрямую добавлять `@rpc`.

### View ничего не решает

View показывает спрайт, направление и анимацию. Он не выбирает цель, не списывает шаг, не наносит урон и не отправляет сеть.

### Host проверяет намерения клиента

Клиент не должен назначать окончательный урон, health, spawn record, AI state или turn snapshot. Для любого нового `@rpc("any_peer")` host обязан проверять роль и отправителя.

### Логи остаются локальными

Нельзя передавать по сети строки logger-функций, stack traces, пути, object dumps или сырые ошибки SDK. По сети идут только данные игрового протокола и ограниченные безопасные причины состояния.

## 15. Важные детали текущей реализации

Эти особенности легко принять за баг, если о них не знать:

- Пошаговый режим не включается автоматически. Без команды `game_turns_enable` игра работает в real-time-подобном свободном режиме.
- Атака разрешена только по ортогонально соседней клетке; диагональная атака невозможна.
- Триггер активности вражеского воина, напротив, учитывает восемь соседних клеток, включая диагонали.
- Уничтоженный дом или дерево меняет вид, но остаётся препятствием.
- Игрок не удаляется после смерти, а сразу возвращается на spawn cell.
- Обычный NPC после смерти удаляется.
- В мировой ход все готовые NPC получают запуск `behavior()`; завершение мирового хода ждёт, пока каждый сообщит о завершении.
- `full_world.tscn` уже содержит House, Tree и Sheep; runtime дополнительно может создать Sheep, Warrior, Tree и House.
- Единственная проходимая поверхность по умолчанию — TileMap-слой `Ground`; `Water` не считается проходимым.
- Сетка логически ограничена `grid_size`, даже если в TileMap нарисованы тайлы за этими границами.

## 16. Текущие ограничения и зоны риска

Это не список требований на немедленную переделку, а ориентир для понимания зрелости проекта:

- UI выбора уровня пока не добавлен; `GameSession` предоставляет каталог и программный выбор по `level_id`.
- Runtime-spawner ограничен четырьмя типами и не является универсальным редактором карты.
- Объекты имеют только бинарное состояние цел/уничтожен и не имеют числового здоровья.
- Непрерывное состояние позиции игрока приходит от клиента. Host проверяет соответствие Steam ID и право действовать в текущем ходу, но в этом пути не пересчитывает полностью клеточную траекторию и коллизии клиента. При развитии соревновательной сетевой модели это важная зона усиления authority-validation.
- Основной gameplay-путь атаки использует общий `broadcast_entity_attack`/`_relay_entity_attack`, а не более узкий `request_attack` с проверкой Steam ID отправителя. Relay-обработчики общих entity events сейчас не проверяют sender ownership для переданного `entity_id`; клиент также запускает локальное применение атаки до получения результата host. Это ключевая зона усиления настоящей host-authoritative модели.
- Часть старых UI/Steam-скриптов использует вывод типов `:=` и широкие `Array`/`Dictionary`. Правила `AGENTS.md` требуют явных типов для нового и изменяемого кода, но не требуют переписывать нетронутый legacy-код только ради стиля.

## 17. Консольные команды проекта

| Команда | Назначение |
|---|---|
| `game_turns_enable` | Включить пошаговый режим; в multiplayer доступно только host. |
| `game_turns_disable` | Выключить пошаговый режим; в multiplayer доступно только host. |
| `game_turns_status` | Показать состояние, раунд, активного игрока и оставшиеся действия. |
| `game_create <type> <x> <y>` | Создать разрешённую сущность или объект, включая `meteor_scroll`, в клетке. |
| `game_inventory_add <item_id> <amount>` | Добавить обычный предмет или свиток, включая `meteor_scroll`, в соответствующий контейнер локального игрока. |
| `game_camera_mode_follow` | Камера плавно следует за локальным персонажем. |
| `game_camera_mode_free` | Камера двигается при приближении курсора к краям экрана. |
| `game_grid_lines_show` | Показать линии проходимых клеток. |
| `game_grid_lines_hide` | Скрыть линии клеток. |

## 18. Термины для новичка

- **Scene (`.tscn`)** — сохранённое дерево узлов Godot. Может быть уровнем, персонажем, объектом или UI-экраном.
- **Node** — один элемент дерева сцены с состоянием и поведением.
- **Autoload** — глобальный узел, который существует при смене сцен. В проекте это `SteamManager`, `GameSession`, `NetworkManager` и `Console`.
- **Runtime** — объекты и состояние, существующие во время запущенного матча.
- **Service** — узел с одной специализированной ответственностью, например сетка или реестр.
- **Facade** — стабильная точка входа, скрывающая детали нескольких сервисов; здесь это `WorldRuntime`.
- **Entity** — подвижный игровой участник с health, damage, клеткой и действиями.
- **GridObject** — статический объект, занимающий одну или несколько клеток.
- **Authority** — сторона, имеющая право окончательно менять общее состояние. Для мира, AI, боя, spawning и ходов это host.
- **Signal** — слабосвязанное событие Godot: отправитель сообщает о случившемся, не управляя внутренностями получателя.
- **RPC** — вызов метода на другом участнике сетевой игры.
- **Reliable** — сообщение должно быть доставлено и подходит для одноразовой команды/результата.
- **Unreliable** — устаревший пакет можно потерять; подходит для часто обновляемого положения.

## 19. Рекомендуемый порядок знакомства с кодом

1. Открыть `project.godot` и увидеть main scene, autoload и Input Map.
2. Посмотреть дерево `full_world.tscn`, не углубляясь в большие данные TileMap.
3. Прочитать `world_level.gd`, `match_controller.gd` и `world_runtime.gd`.
4. По очереди изучить `WorldGrid`, `WorldRegistry`, `WorldPlayers`, `WorldCombat` и `WorldTurns`.
5. Пройти цепочку `CharacterModel → PlayerCharacter → Entity → WorldRuntime`.
6. Изучить `NonPlayerEntity`, затем простую `Sheep` и только после этого большой `Warrior` AI.
7. Для multiplayer читать в порядке `GameSession → SteamManager → NetworkManager → WorldNetwork`.
8. В конце посмотреть views, HUD, camera, grid visualization и menu UI: они проще, когда понятен домен.

Такой порядок движется от владельцев жизненного цикла и данных к деталям поведения и помогает не принять конкретную сцену уровня за архитектурный центр всего приложения.
