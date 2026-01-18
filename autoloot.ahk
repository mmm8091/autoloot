#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Event"  ; 【关键】使用 Event 模式以支持按键时长模拟
SetWorkingDir A_ScriptDir

; ==============================================================================
; ⚙️ 全局配置 (可在此调整参数)
; ==============================================================================
global IniFileName := "config.ini"
global DefaultInterval := 1000
global MinInterval := 50
global DriftChangeRate := 0.05
global MaxDrift := 1.2
global MinDrift := 0.8

; 全局状态控制
global GlobalPaused := true  ; 默认启动时为暂停状态
global ActiveKeys := Map()   ; 内存中的按键状态表

; ==============================================================================
; 🖥️ OSD 屏幕显示初始化 (修复布局版)
; ==============================================================================
global MyOSD := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
MyOSD.BackColor := "1F1F1F"
MyOSD.SetFont("s10", "Microsoft YaHei UI")
WinSetTransparent(210, MyOSD)

; 1. 标题 (居中，加粗)
MyOSD.SetFont("s11 w700")
global OSDHeader := MyOSD.Add("Text", "w220 Center vHeader", "初始化...")

; 2. 分割线
MyOSD.Add("Text", "h2 w230 0x10") ; 稍微宽一点以填满

; 3. 详细列表 (关键修改：改为 Left 左对齐，去掉预设高度)
; 使用 Consolas 字体确保数字对齐
MyOSD.SetFont("s10 w400", "Consolas")
; 注意：这里不设高度，留给后面 UpdateOSD 自动控制
global OSDContent := MyOSD.Add("Text", "w220 Left vContent cWhite y+5 x15", "")

; 允许鼠标拖动窗口
OnMessage(0x0201, WM_LBUTTONDOWN)

MyOSD.Show("NoActivate x50 y50 AutoSize")
; ==============================================================================
; 🚀 启动加载逻辑
; ==============================================================================
LoadConfig() ; 读取配置文件

; ==============================================================================
; 🎮 热键注册
; ==============================================================================

; 1. 注册 F12 总开关
Hotkey "F12", ToggleGlobalPause

; 2. 批量注册单键开关 (Ctrl+Alt+Shift + Key)
SupportKeys := []
Loop 26
    SupportKeys.Push(Chr(A_Index + 64)) ; A-Z
Loop 10
    SupportKeys.Push(String(A_Index - 1)) ; 0-9
Loop 12
    SupportKeys.Push("F" . A_Index) ; F1-F12
SymbolKeys := ["[", "]", ";", "'", ",", ".", "/", "-", "="]
Loop SymbolKeys.Length
    SupportKeys.Push(SymbolKeys[A_Index])

for key in SupportKeys {
    Hotkey("^+!" . key, ToggleKeyMacro.Bind(key))
}

; 3. 注册调速热键 (仅在按住对应键时生效)
IsHoldingActiveKey() {
    for key in ActiveKeys {
        if GetKeyState(key, "P")
            return true
    }
    return false
}

#HotIf IsHoldingActiveKey()
    =::AdjustSpeed(100)          ; 主键盘 + (实际是等号键)
    -::AdjustSpeed(-100)         ; 主键盘 -
    NumpadAdd::AdjustSpeed(100)  ; 小键盘 +
    NumpadSub::AdjustSpeed(-100) ; 小键盘 -
#HotIf

; ==============================================================================
; 🧠 核心逻辑函数
; ==============================================================================

/**
 * F12 总开关逻辑
 */
ToggleGlobalPause(*) {
    global GlobalPaused := !GlobalPaused
    
    if (GlobalPaused) {
        SoundBeep(500, 150) ; 🔕 暂停音效 (低)
    } else {
        SoundBeep(1500, 150) ; 🔔 启动音效 (高)
        ; 恢复时，立即重置所有定时器，防止堆积
        for key, state in ActiveKeys {
             SetTimer(state.Timer, -10)
        }
    }
    UpdateOSD()
}

/**
 * 单键开关逻辑 (逻辑A: 彻底删除)
 */
ToggleKeyMacro(keyName, *) {
    keyName := StrLower(keyName)
    
    if (ActiveKeys.Has(keyName)) {
        ; --- 关闭逻辑 ---
        StopKey(keyName)
        IniDelete IniFileName, "ActiveKeys", keyName ; 从文件删除
        SoundBeep(750, 100)
    } else {
        ; --- 开启逻辑 ---
        AddKey(keyName, DefaultInterval)
        SaveKeyConfig(keyName, DefaultInterval)      ; 写入文件
        SoundBeep(1200, 100)
    }
    UpdateOSD()
}

/**
 * 添加按键到内存并启动定时器
 */
AddKey(keyName, interval) {
    if ActiveKeys.Has(keyName)
        return

    state := {}
    state.BaseDelay := Integer(interval)
    state.Drift := 1.0  
    state.Timer := KeyClickLoop.Bind(keyName)
    
    ActiveKeys[keyName] := state
    
    ; 启动定时器 (如果总开关是暂停的，定时器会在回调里自动Return，不执行动作)
    SetTimer(state.Timer, -10) 
}

/**
 * 停止并从内存移除
 */
StopKey(keyName) {
    if ActiveKeys.Has(keyName) {
        try {
            SetTimer(ActiveKeys[keyName].Timer, 0)
        }
        ActiveKeys.Delete(keyName)
    }
}

/**
 * 🎯 核心执行循环 (包含防封逻辑)
 */
KeyClickLoop(keyName) {
    if !ActiveKeys.Has(keyName)
        return

    ; 【总闸检查】如果暂停中，只把定时器设为“稍后重试”，不执行点击
    if (GlobalPaused) {
        SetTimer(ActiveKeys[keyName].Timer, -1000) ; 每秒检查一次是否解除了暂停
        return
    }

    ; --- 动作执行阶段 ---
    
    ; 1. 模拟人类按下动作：按下 -> 随机保持 40-90ms -> 松开
    SendEvent "{" . keyName . " down}"
    Sleep(Random(40, 90)) 
    SendEvent "{" . keyName . " up}"

    ; --- 下次间隔计算阶段 (二阶随机) ---
    state := ActiveKeys[keyName]

    driftDelta := (Random(0, 100) / 1000.0) - 0.05 
    state.Drift += driftDelta
    if (state.Drift > MaxDrift)
        state.Drift := MaxDrift
    else if (state.Drift < MinDrift)
        state.Drift := MinDrift

    centerInterval := state.BaseDelay * state.Drift
    jitter := centerInterval * 0.1
    finalInterval := centerInterval + Random(-jitter, jitter)

    if (finalInterval < 50)
        finalInterval := 50

    ; 减去刚才按键消耗掉的 Sleep 时间，保证总体频率准确
    finalWait := Integer(finalInterval)
    if (finalWait < 10)
        finalWait := 10

    SetTimer(state.Timer, -finalWait)
}

/**
 * 调速并保存
 */
AdjustSpeed(amount, *) {
    for keyName, state in ActiveKeys {
        if GetKeyState(keyName, "P") {
            state.BaseDelay += amount
            if (state.BaseDelay < MinInterval)
                state.BaseDelay := MinInterval
            
            ; 实时保存到文件
            SaveKeyConfig(keyName, state.BaseDelay)
            
            ; 语音反馈
            try {
                ComObject("SAPI.SpVoice").Speak(state.BaseDelay)
            }
            
            UpdateOSD()
            return 
        }
    }
}

; ==============================================================================
; 💾 读写配置相关
; ==============================================================================

LoadConfig() {
    try {
        ; 读取 Ini 文件中的 [ActiveKeys] 章节
        activeSection := IniRead(IniFileName, "ActiveKeys", "")
        
        if (activeSection = "")
            return

        ; 解析每一行 (格式: key=interval)
        Loop Parse, activeSection, "`n", "`r" 
        {
            if (A_LoopField = "")
                continue
                
            parts := StrSplit(A_LoopField, "=")
            if (parts.Length = 2) {
                key := parts[1]
                interval := parts[2]
                AddKey(key, interval)
            }
        }
    }
    UpdateOSD()
}

SaveKeyConfig(key, interval) {
    IniWrite interval, IniFileName, "ActiveKeys", key
}

; ==============================================================================
; 🖥️ OSD 更新逻辑 (强制刷新高度)
; ==============================================================================
UpdateOSD() {
    activeCount := ActiveKeys.Count

    ; --- 1. 标题颜色与状态 ---
    if (GlobalPaused) {
        OSDHeader.SetFont("cFFAA00")
        OSDHeader.Value := "⏸ PAUSED (" . activeCount . "键)"
        MyOSD.BackColor := "2D2D2D"
    } else {
        OSDHeader.SetFont("c00FF7F")
        OSDHeader.Value := "⚡ RUNNING (" . activeCount . "键)"
        MyOSD.BackColor := "1F1F1F"
    }
    
    ; --- 2. 构建列表内容 ---
    keyListStr := ""
    
    if (activeCount == 0) {
        keyListStr := "等待热键激活...`n(Ctrl+Alt+Shift+Key)"
        OSDContent.SetFont("cGray")
    } else {
        ; 遍历所有按键
        for key, state in ActiveKeys {
            uKey := StrUpper(key)
            
            ; 简单的对齐填充
            padding := ""
            if (StrLen(uKey) < 2)
                padding := "  "
            else if (StrLen(uKey) < 4)
                padding := " "
            
            ; 【关键点】这里必须是 .= (点加等号) 才是追加，如果是 := 就会覆盖
            keyListStr .= Format("{1}{2} ➜ {3,4} ms`n", uKey, padding, state.BaseDelay)
        }
        ; 去掉末尾多余换行
        keyListStr := RTrim(keyListStr, "`n")
        OSDContent.SetFont("cWhite")
    }

    ; --- 3. 赋值与强制重绘 (修复显示不全的问题) ---
    OSDContent.Value := keyListStr
    
    ; 【核心修复】告诉文本控件：保持宽度220，高度自动适应内容(空字符串代表自动)
    OSDContent.Move(,, 220)
    
    ; 最后调整整个窗口大小以适应新的控件高度
    MyOSD.Show("AutoSize NoActivate")
}
; ==============================================================================
; 🖱️ 窗口拖拽逻辑 (关键补充)
; ==============================================================================
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    ; 仅当消息来源是我们的 OSD 窗口时才触发拖拽
    if (hwnd = MyOSD.Hwnd)
        PostMessage 0xA1, 2, 0, hwnd ; 发送拖拽指令
}