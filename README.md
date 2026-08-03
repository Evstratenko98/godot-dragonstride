# DragonStride

DragonStride — сетевой 2D-проект на Godot 4.6 с клеточным миром, пошаговым режимом
и Steam-мультиплеером.

Для первого знакомства начните с [PROJECT_GUIDE_RU.md](PROJECT_GUIDE_RU.md), затем
прочитайте [AGENTS.md](AGENTS.md) перед любым изменением исходного кода.

Короткий маршрут:

1. Откройте project.godot и запустите проект в Godot 4.6.
2. Считайте scenes/world/match_world.tscn оболочкой матча, а
   scenes/sandbox/sandbox.tscn — только тестовым уровнем.
3. Новые gameplay-возможности проводите через WorldRuntime к одному профильному
   World-сервису; UI и views не должны владеть игровыми правилами или сетью.
4. После изменения запустите headless-проверку Godot и git diff --check.