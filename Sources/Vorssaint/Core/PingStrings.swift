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
    let remove: String
    let invalidTarget: String
    let measuring: String
    let targetsTitle: String
    let otherTarget: String
    let targetsCaption: String
    let menuBarTarget: String
    let noTargets: String
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
        unresolved: "Can’t resolve",
        unavailable: "Ping unavailable",
        loss: "Loss",
        remove: "Remove",
        invalidTarget: "Enter a host, domain or IP address",
        measuring: "Measuring…",
        targetsTitle: "Ping targets",
        otherTarget: "Other host…",
        targetsCaption: "Pinged while the Ping block is shown in the panel or the Ping menu bar item is on.",
        menuBarTarget: "Ping target",
        noTargets: "No ping targets"
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
        remove: "Remover",
        invalidTarget: "Digite um host, domínio ou endereço IP",
        measuring: "Medindo…",
        targetsTitle: "Destinos de ping",
        otherTarget: "Outro host…",
        targetsCaption: "Recebem ping enquanto o bloco Ping aparece no painel ou o item Ping da barra de menus está ativo.",
        menuBarTarget: "Destino do ping",
        noTargets: "Nenhum destino de ping"
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
        remove: "Kaldır",
        invalidTarget: "Bir ana makine, alan adı veya IP adresi girin",
        measuring: "Ölçülüyor…",
        targetsTitle: "Ping hedefleri",
        otherTarget: "Başka ana makine…",
        targetsCaption: "Ping bloğu panelde gösterilirken veya Ping menü çubuğu öğesi açıkken pinglenir.",
        menuBarTarget: "Ping hedefi",
        noTargets: "Ping hedefi yok"
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
        remove: "Удалить",
        invalidTarget: "Введите хост, домен или IP-адрес",
        measuring: "Измерение…",
        targetsTitle: "Узлы для пинга",
        otherTarget: "Другой хост…",
        targetsCaption: "Пингуются, пока блок «Пинг» показан на панели или включён пункт «Пинг» в строке меню.",
        menuBarTarget: "Узел для пинга",
        noTargets: "Нет узлов для пинга"
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
        remove: "Eliminar",
        invalidTarget: "Introduce un host, dominio o dirección IP",
        measuring: "Midiendo…",
        targetsTitle: "Destinos de ping",
        otherTarget: "Otro host…",
        targetsCaption: "Se hace ping mientras el bloque Ping se muestra en el panel o el elemento Ping de la barra de menús está activado.",
        menuBarTarget: "Destino del ping",
        noTargets: "No hay destinos de ping"
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
        remove: "Odstrániť",
        invalidTarget: "Zadajte hostiteľa, doménu alebo IP adresu",
        measuring: "Meria sa…",
        targetsTitle: "Ciele pingu",
        otherTarget: "Iný hostiteľ…",
        targetsCaption: "Pingujú sa, kým je blok Ping zobrazený na paneli alebo je zapnutá položka Ping v lište ponúk.",
        menuBarTarget: "Cieľ pingu",
        noTargets: "Žiadne ciele pingu"
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
        remove: "Entfernen",
        invalidTarget: "Host, Domain oder IP-Adresse eingeben",
        measuring: "Wird gemessen…",
        targetsTitle: "Ping-Ziele",
        otherTarget: "Anderer Host…",
        targetsCaption: "Wird angepingt, solange der Ping-Block im Panel angezeigt wird oder das Ping-Element in der Menüleiste aktiv ist.",
        menuBarTarget: "Ping-Ziel",
        noTargets: "Keine Ping-Ziele"
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
        remove: "Supprimer",
        invalidTarget: "Saisissez un hôte, un domaine ou une adresse IP",
        measuring: "Mesure…",
        targetsTitle: "Cibles du ping",
        otherTarget: "Autre hôte…",
        targetsCaption: "Pinguées tant que le bloc Ping est affiché dans le panneau ou que l’élément Ping de la barre des menus est activé.",
        menuBarTarget: "Cible du ping",
        noTargets: "Aucune cible de ping"
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
        remove: "Rimuovi",
        invalidTarget: "Inserisci un host, un dominio o un indirizzo IP",
        measuring: "Misurazione…",
        targetsTitle: "Destinazioni ping",
        otherTarget: "Altro host…",
        targetsCaption: "Ricevono il ping mentre il blocco Ping è visibile nel pannello o l’elemento Ping della barra dei menu è attivo.",
        menuBarTarget: "Destinazione ping",
        noTargets: "Nessuna destinazione ping"
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
        remove: "削除",
        invalidTarget: "ホスト、ドメイン、またはIPアドレスを入力してください",
        measuring: "計測中…",
        targetsTitle: "Ping の宛先",
        otherTarget: "その他のホスト…",
        targetsCaption: "パネルに Ping ブロックが表示されているか、メニューバーの Ping 項目がオンのときに Ping を送信します。",
        menuBarTarget: "Ping の宛先",
        noTargets: "Ping の宛先がありません"
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
        remove: "제거",
        invalidTarget: "호스트, 도메인 또는 IP 주소를 입력하세요",
        measuring: "측정 중…",
        targetsTitle: "핑 대상",
        otherTarget: "다른 호스트…",
        targetsCaption: "패널에 핑 블록이 표시되거나 메뉴 막대의 핑 항목이 켜져 있는 동안 핑을 보냅니다.",
        menuBarTarget: "핑 대상",
        noTargets: "핑 대상 없음"
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
        remove: "移除",
        invalidTarget: "请输入主机、域名或 IP 地址",
        measuring: "正在测量…",
        targetsTitle: "Ping 目标",
        otherTarget: "其他主机…",
        targetsCaption: "在面板中显示 Ping 模块或菜单栏中的 Ping 项目开启时进行 Ping。",
        menuBarTarget: "Ping 目标",
        noTargets: "没有 Ping 目标"
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
        remove: "移除",
        invalidTarget: "請輸入主機、網域或 IP 位址",
        measuring: "正在測量…",
        targetsTitle: "Ping 目標",
        otherTarget: "其他主機…",
        targetsCaption: "在面板中顯示 Ping 區塊或選單列中的 Ping 項目開啟時進行 Ping。",
        menuBarTarget: "Ping 目標",
        noTargets: "沒有 Ping 目標"
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
        remove: "移除",
        invalidTarget: "請輸入主機、網域或 IP 位址",
        measuring: "正在測量…",
        targetsTitle: "Ping 目標",
        otherTarget: "其他主機…",
        targetsCaption: "在面板中顯示 Ping 區塊或選單列中的 Ping 項目開啟時進行 Ping。",
        menuBarTarget: "Ping 目標",
        noTargets: "沒有 Ping 目標"
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
        remove: "Вилучити",
        invalidTarget: "Введіть хост, домен або IP-адресу",
        measuring: "Вимірювання…",
        targetsTitle: "Вузли для пінгу",
        otherTarget: "Інший хост…",
        targetsCaption: "Пінгуються, поки блок «Пінг» показано на панелі або ввімкнено пункт «Пінг» у рядку меню.",
        menuBarTarget: "Вузол для пінгу",
        noTargets: "Немає вузлів для пінгу"
    )
}
