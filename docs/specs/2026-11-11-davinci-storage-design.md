# DaVinci Storage — дизайн (MVP)

Дата: 2026-11-11 · Автор: Artem (artveli.color) + Claude

## Мета
Нативна macOS-програма, яка показує, скільки місця на диску займає кожен проєкт DaVinci Resolve
(кеш, бекапи, стіли, Magic Mask), знаходить залишки видалених проєктів і дублі,
та дозволяє безпечно перемістити непотрібне в Кошик.

**Успіх:** відкриваю програму → бачу кожен проєкт за назвою з розмірами та віком → позначаю
старі (> N місяців) або видалені → «В Кошик» → місце звільнено, DaVinci працює як раніше.

## Обмеження
- macOS 27, Apple Silicon, лише Command Line Tools (Swift 6.4, Swift Testing), без Xcode.
- Збирання через SwiftPM, .app пакується скриптом, ad-hoc підпис. Тільки для власного Mac.
- Бази проєктів (`Project.db`, `User.db`, бібліотеки) — **тільки читання**, ніколи не змінюються.
- Видалення — **тільки в Кошик** (`FileManager.trashItem`), ніколи `rm`.
- Поки DaVinci Resolve запущений — кнопка очищення вимкнена.

## Звідки беремо дані (перевірено на цьому Mac)
| Що | Джерело | Як прив'язується до проєкту |
|---|---|---|
| Бібліотеки | `~/Library/Preferences/Blackmagic Design/DaVinci Resolve/dblist.conf` (тип `DISK`) | — |
| Проєкти | `<бібліотека>/Resolve Projects/Users/*/Projects/**/Project.db` → таблиця `SM_Project` (`SM_Project_id`, `ProjectName`, `LastModTimeInSecs`) | UUID = `SM_Project_id` |
| Кеш рендеру | `~/Movies/CacheClip/<UUID>`, `/Library/Application Support/Blackmagic Design/DaVinci Resolve/CacheClip/<UUID>` + шляхи з налаштувань проєкту | UUID у назві папки |
| Бекапи | `ProjectBackupLocation` з `config.user.xml` (зараз `~/Movies/Resolve Project Backups/<UUID>`) | UUID у назві папки |
| Стіли (нові) | `~/Movies/.gallery/<UUID>/` з `Info.txt` (Database/Project Name) | UUID + Info.txt |
| Стіли (старі) | `/Library/Application Support/Blackmagic Design/DaVinci Resolve/.gallery` (`<StillUUID>.dpx`) | `Gallery::GyStill` у Project.db |
| Magic Mask | шляхи, записані в Project.db (напр. `~/DaVinci Resolve Media/UKRAVIT/Magic Mask`), + корені `~/MAGIC_MASK_2_DAVINCI`, `~/DaVinci Resolve Media` | шлях з Project.db; інакше — за назвою папки (позначка «за назвою, неточно») |
| Проксі / Optimized Media | `/Library/Application Support/Blackmagic Design/DaVinci Resolve/ProxyMedia`, `ProxyMedia`/`OptimizedMedia` поруч із кожним коренем CacheClip, + «Proxy generation location» з налаштувань проєкту (зараз папок немає — показуємо 0 / «не знайдено») | шлях з Project.db; інакше — за назвою підпапки (позначка «за назвою, неточно») |
| Службові кеші | `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/.LUT`, `~/Library/Caches/com.blackmagic-design.DaVinciResolve` | не прив'язані |
| Frame.io | локальна папка кешу з Preferences → System → Internet Accounts (зараз не налаштована — ключ визначимо після першого рендеру; до того показуємо «не знайдено») | не прив'язана |

## Компоненти
1. **ResolveConfig** — читає `dblist.conf`, `config.user.xml`, `config.dat`: бібліотеки, шлях бекапів, назви папок кешу/галереї.
2. **ProjectReader** — відкриває Project.db через SQLite3 (`mode=ro`), повертає `Project {id, name, library, folderPath, lastModified, stillIDs, magicMaskPaths}`.
3. **StorageScanner** — обходить усі джерела, рахує розміри папок, повертає `Item {category, path, bytes, projectID?, matchKind}`.
4. **Analyzer** — зводить у `Report`: рядки проєктів з розмірами по категоріях; «Видалені проєкти» (UUID без проєкту в жодній бібліотеці); «Дублі» (Magic Mask з однаковими файлами в двох коренях — однакова назва + розмір); службові кеші.
5. **Cleaner** — переміщує вибрані шляхи в Кошик, перевіряючи, що шлях лежить у дозволених коренях і не є базою проєкту; повертає звіт.
6. **CLI** (`davinci-storage report`) — друкує звіт у Терміналі (перший етап, для звірки цифр).
7. **App (SwiftUI)** — вікно з трьома розділами.

## Інтерфейс
Бокова панель:
- **Проєкти** — таблиця: Назва · Бібліотека · Остання зміна · Кеш · Бекапи · Стіли · Magic Mask · Проксі · Разом. Сортування за будь-якою колонкою. Фільтр «старші за [3] місяці». Галочки по рядку та по категоріях.
- **Видалені проєкти і дублі** — групи за UUID/назвою з розміром і поясненням, звідки відомо.
- **Службові кеші** — `.LUT` (з поясненням: DaVinci відтворить сам), кеш програми, Frame.io.

Внизу: «Вибрано: X ГБ» + кнопка «Перемістити в Кошик…» → аркуш підтвердження зі списком шляхів.
Банер, якщо DaVinci запущений. Кнопка «Сканувати знову».

## Обробка помилок
- Project.db заблокований/пошкоджений → проєкт показується з позначкою «не вдалося прочитати», його файли не вважаються видаленими.
- Немає доступу до папки → рядок з попередженням, сканування продовжується.
- Шлях поза дозволеними коренями → Cleaner відмовляє.

## Тестування
- Swift Testing: парсери конфігів і Project.db на фікстурах (копії реальних конфігів + маленька тестова SQLite-база), Analyzer на синтетичних деревах папок, Cleaner — відмова для заборонених шляхів.
- Ручна звірка: CLI-звіт проти `du -sh` на реальних папках.
- Скріншот вікна після збирання.

## Поза MVP (YAGNI)
Архів проєкту в .drp перед очищенням, підтримка PostgreSQL-баз, розклад/нагадування, роздача іншим (нотаризація).

## Розташування
Код: `/Users/artveli/CLAUDE_PROJECT/DAVINCI_STORAGE`. Готова програма: `~/Applications/DaVinci Storage.app`.
