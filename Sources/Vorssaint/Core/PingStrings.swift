// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PingFeatureStrings {
    let title: String
    let addTarget: String
    let targetPlaceholder: String
    let router: String
    let down: String
    let menuBarDown: String
    let resolving: String
    let unresolved: String
    let unavailable: String
    let loss: String
    let showInMenuBar: String
    let shownInMenuBar: String
    let remove: String
    let invalidTarget: String
    let measuring: String
}

extension FeatureStrings {
    static func ping(_ language: AppLanguage) -> PingFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension PingFeatureStrings {
    static let enUS = PingFeatureStrings(
        title: "Ping",
        addTarget: "Add target",
        targetPlaceholder: "Host, domain or IP",
        router: "Router",
        down: "Down",
        menuBarDown: "DOWN",
        resolving: "Resolving…",
        unresolved: "Can't resolve",
        unavailable: "Ping unavailable",
        loss: "Loss",
        showInMenuBar: "Show in menu bar",
        shownInMenuBar: "Shown in menu bar",
        remove: "Remove",
        invalidTarget: "Enter a host, domain or IP address",
        measuring: "Measuring…"
    )

    static let ptBR = PingFeatureStrings(
        title: "Ping",
        addTarget: "Adicionar destino",
        targetPlaceholder: "Host, domínio ou IP",
        router: "Roteador",
        down: "Inativo",
        menuBarDown: "OFF",
        resolving: "Resolvendo…",
        unresolved: "Não foi possível resolver",
        unavailable: "Ping indisponível",
        loss: "Perda",
        showInMenuBar: "Mostrar na barra de menus",
        shownInMenuBar: "Mostrado na barra de menus",
        remove: "Remover",
        invalidTarget: "Digite um host, domínio ou endereço IP",
        measuring: "Medindo…"
    )

    static let tr = PingFeatureStrings(
        title: "Ping",
        addTarget: "Hedef ekle",
        targetPlaceholder: "Ana makine, alan adı veya IP",
        router: "Yönlendirici",
        down: "Kapalı",
        menuBarDown: "YOK",
        resolving: "Çözümleniyor…",
        unresolved: "Çözümlenemiyor",
        unavailable: "Ping kullanılamıyor",
        loss: "Kayıp",
        showInMenuBar: "Menü çubuğunda göster",
        shownInMenuBar: "Menü çubuğunda gösteriliyor",
        remove: "Kaldır",
        invalidTarget: "Bir ana makine, alan adı veya IP adresi girin",
        measuring: "Ölçülüyor…"
    )

    static let ru = PingFeatureStrings(
        title: "Пинг",
        addTarget: "Добавить узел",
        targetPlaceholder: "Хост, домен или IP",
        router: "Роутер",
        down: "Недоступен",
        menuBarDown: "НЕТ",
        resolving: "Определение адреса…",
        unresolved: "Не удаётся определить адрес",
        unavailable: "Пинг недоступен",
        loss: "Потери",
        showInMenuBar: "Показывать в строке меню",
        shownInMenuBar: "Показано в строке меню",
        remove: "Удалить",
        invalidTarget: "Введите хост, домен или IP-адрес",
        measuring: "Измерение…"
    )

    static let es = PingFeatureStrings(
        title: "Ping",
        addTarget: "Añadir destino",
        targetPlaceholder: "Host, dominio o IP",
        router: "Router",
        down: "Caído",
        menuBarDown: "CAÍDO",
        resolving: "Resolviendo…",
        unresolved: "No se puede resolver",
        unavailable: "Ping no disponible",
        loss: "Pérdida",
        showInMenuBar: "Mostrar en la barra de menús",
        shownInMenuBar: "Se muestra en la barra de menús",
        remove: "Eliminar",
        invalidTarget: "Introduce un host, dominio o dirección IP",
        measuring: "Midiendo…"
    )

    static let sk = PingFeatureStrings(
        title: "Ping",
        addTarget: "Pridať cieľ",
        targetPlaceholder: "Hostiteľ, doména alebo IP",
        router: "Smerovač",
        down: "Nedostupný",
        menuBarDown: "VYP",
        resolving: "Prekladá sa…",
        unresolved: "Nedá sa preložiť",
        unavailable: "Ping nie je dostupný",
        loss: "Strata",
        showInMenuBar: "Zobraziť v lište ponúk",
        shownInMenuBar: "Zobrazené v lište ponúk",
        remove: "Odstrániť",
        invalidTarget: "Zadajte hostiteľa, doménu alebo IP adresu",
        measuring: "Meria sa…"
    )

    static let de = PingFeatureStrings(
        title: "Ping",
        addTarget: "Ziel hinzufügen",
        targetPlaceholder: "Host, Domain oder IP",
        router: "Router",
        down: "Nicht erreichbar",
        menuBarDown: "AUS",
        resolving: "Wird aufgelöst…",
        unresolved: "Nicht auflösbar",
        unavailable: "Ping nicht verfügbar",
        loss: "Verlust",
        showInMenuBar: "In der Menüleiste zeigen",
        shownInMenuBar: "In der Menüleiste gezeigt",
        remove: "Entfernen",
        invalidTarget: "Host, Domain oder IP-Adresse eingeben",
        measuring: "Wird gemessen…"
    )

    static let fr = PingFeatureStrings(
        title: "Ping",
        addTarget: "Ajouter une cible",
        targetPlaceholder: "Hôte, domaine ou IP",
        router: "Routeur",
        down: "Injoignable",
        menuBarDown: "HS",
        resolving: "Résolution…",
        unresolved: "Résolution impossible",
        unavailable: "Ping indisponible",
        loss: "Perte",
        showInMenuBar: "Afficher dans la barre des menus",
        shownInMenuBar: "Affiché dans la barre des menus",
        remove: "Supprimer",
        invalidTarget: "Saisissez un hôte, un domaine ou une adresse IP",
        measuring: "Mesure…"
    )

    static let it = PingFeatureStrings(
        title: "Ping",
        addTarget: "Aggiungi destinazione",
        targetPlaceholder: "Host, dominio o IP",
        router: "Router",
        down: "Non raggiungibile",
        menuBarDown: "OFF",
        resolving: "Risoluzione…",
        unresolved: "Impossibile risolvere",
        unavailable: "Ping non disponibile",
        loss: "Perdita",
        showInMenuBar: "Mostra nella barra dei menu",
        shownInMenuBar: "Mostrato nella barra dei menu",
        remove: "Rimuovi",
        invalidTarget: "Inserisci un host, un dominio o un indirizzo IP",
        measuring: "Misurazione…"
    )

    static let ja = PingFeatureStrings(
        title: "Ping",
        addTarget: "宛先を追加",
        targetPlaceholder: "ホスト、ドメイン、IP",
        router: "ルーター",
        down: "応答なし",
        menuBarDown: "断",
        resolving: "名前解決中…",
        unresolved: "名前を解決できません",
        unavailable: "Pingを利用できません",
        loss: "損失",
        showInMenuBar: "メニューバーに表示",
        shownInMenuBar: "メニューバーに表示中",
        remove: "削除",
        invalidTarget: "ホスト、ドメイン、またはIPアドレスを入力してください",
        measuring: "計測中…"
    )

    static let ko = PingFeatureStrings(
        title: "핑",
        addTarget: "대상 추가",
        targetPlaceholder: "호스트, 도메인 또는 IP",
        router: "라우터",
        down: "응답 없음",
        menuBarDown: "끊김",
        resolving: "확인 중…",
        unresolved: "확인할 수 없음",
        unavailable: "핑을 사용할 수 없음",
        loss: "손실",
        showInMenuBar: "메뉴 막대에 표시",
        shownInMenuBar: "메뉴 막대에 표시됨",
        remove: "제거",
        invalidTarget: "호스트, 도메인 또는 IP 주소를 입력하세요",
        measuring: "측정 중…"
    )

    static let zhHans = PingFeatureStrings(
        title: "Ping",
        addTarget: "添加目标",
        targetPlaceholder: "主机、域名或 IP",
        router: "路由器",
        down: "不可达",
        menuBarDown: "断开",
        resolving: "正在解析…",
        unresolved: "无法解析",
        unavailable: "Ping 不可用",
        loss: "丢包",
        showInMenuBar: "在菜单栏中显示",
        shownInMenuBar: "已在菜单栏中显示",
        remove: "移除",
        invalidTarget: "请输入主机、域名或 IP 地址",
        measuring: "正在测量…"
    )

    static let zhTW = PingFeatureStrings(
        title: "Ping",
        addTarget: "加入目標",
        targetPlaceholder: "主機、網域或 IP",
        router: "路由器",
        down: "無法連線",
        menuBarDown: "中斷",
        resolving: "正在解析…",
        unresolved: "無法解析",
        unavailable: "無法使用 Ping",
        loss: "遺失",
        showInMenuBar: "在選單列中顯示",
        shownInMenuBar: "已在選單列中顯示",
        remove: "移除",
        invalidTarget: "請輸入主機、網域或 IP 位址",
        measuring: "正在測量…"
    )

    static let zhHK = PingFeatureStrings(
        title: "Ping",
        addTarget: "加入目標",
        targetPlaceholder: "主機、網域或 IP",
        router: "路由器",
        down: "無法連線",
        menuBarDown: "中斷",
        resolving: "正在解析…",
        unresolved: "無法解析",
        unavailable: "無法使用 Ping",
        loss: "遺失",
        showInMenuBar: "在選單列中顯示",
        shownInMenuBar: "已在選單列中顯示",
        remove: "移除",
        invalidTarget: "請輸入主機、網域或 IP 位址",
        measuring: "正在測量…"
    )

    static let uk = PingFeatureStrings(
        title: "Пінг",
        addTarget: "Додати вузол",
        targetPlaceholder: "Хост, домен або IP",
        router: "Роутер",
        down: "Недоступний",
        menuBarDown: "НЕМАЄ",
        resolving: "Визначення адреси…",
        unresolved: "Не вдається визначити адресу",
        unavailable: "Пінг недоступний",
        loss: "Втрати",
        showInMenuBar: "Показувати в рядку меню",
        shownInMenuBar: "Показано в рядку меню",
        remove: "Вилучити",
        invalidTarget: "Введіть хост, домен або IP-адресу",
        measuring: "Вимірювання…"
    )
}
