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
; 🖥️ OSD 屏幕显示初始化 (重构版)
; ==============================================================================
InitOSD() {
    global MyOSD, OSDHeader, OSDContent
    
    ; 创建 GUI 窗口
    MyOSD := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    MyOSD.BackColor := "1F1F1F"
    WinSetTransparent(210, MyOSD)
    
    ; 设置默认字体
    MyOSD.SetFont("s10", "Microsoft YaHei UI")
    
    ; 1. 标题 (居中，加粗)
    MyOSD.SetFont("s11 w700")
    OSDHeader := MyOSD.Add("Text", "w240 Center vHeader", "初始化...")
    
    ; 2. 分割线
    MyOSD.Add("Text", "h2 w240 0x10")
    
    ; 3. 内容区域 - 使用 Edit 控件支持多行显示
    MyOSD.SetFont("s10 w400", "Consolas")
    OSDContent := MyOSD.Add("Edit", "w240 r10 ReadOnly -VScroll -HScroll vContent cWhite Background1F1F1F")
    ; ReadOnly: 只读
    ; r10: 初始10行，后续会动态调整
    ; -VScroll -HScroll: 禁用滚动条（让窗口自动扩展）
    ; Background1F1F1F: 设置背景色与窗口一致
    
    ; 允许鼠标拖动窗口
    OnMessage(0x0201, WM_LBUTTONDOWN)
    
    ; 显示窗口
    MyOSD.Show("NoActivate x50 y50 AutoSize")
}

; 初始化 OSD
InitOSD()
; ==============================================================================
; 🚀 启动加载逻辑
; ==============================================================================
global ConfigFileTime := 0  ; 记录配置文件最后修改时间
LoadConfig() ; 读取配置文件
StartConfigMonitor() ; 启动配置文件监控

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
        ; 🔕 暂停音效：低音三连音（更复杂的声音）
        SoundBeep(400, 100)
        Sleep(50)
        SoundBeep(350, 100)
        Sleep(50)
        SoundBeep(300, 150)
    } else {
        ; 🔔 启动音效：高音上升音阶（更复杂的声音）
        SoundBeep(800, 80)
        Sleep(40)
        SoundBeep(1000, 80)
        Sleep(40)
        SoundBeep(1200, 80)
        Sleep(40)
        SoundBeep(1500, 120)
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
; 💾 读写配置相关 (重构版)
; ==============================================================================

LoadConfig() {
    global ConfigFileTime
    
    ; 检查文件是否存在
    if !FileExist(IniFileName) {
        UpdateOSD()
        return
    }
    
    ; 获取文件修改时间
    try {
        fileTime := FileGetTime(IniFileName, "M")
        ConfigFileTime := fileTime
    } catch {
        ; 如果获取时间失败，继续执行
    }
    
    ; 先停止所有现有的按键
    keysToStop := []
    for key in ActiveKeys {
        keysToStop.Push(key)
    }
    for key in keysToStop {
        StopKey(key)
    }
    
    ; 读取配置文件
    try {
        ; 读取整个 [ActiveKeys] 章节
        activeSection := IniRead(IniFileName, "ActiveKeys")
        
        if (activeSection = "" || activeSection = "ERROR") {
            UpdateOSD()
            return
        }

        ; 解析每一行 (格式: key=interval)
        lines := StrSplit(activeSection, "`n", "`r")
        for line in lines {
            line := Trim(line)
            if (line = "")
                continue
            
            ; 分割键值对
            pos := InStr(line, "=")
            if (pos <= 0)
                continue
            
            key := Trim(SubStr(line, 1, pos - 1))
            intervalStr := Trim(SubStr(line, pos + 1))
            
            ; 验证并添加
            if (key != "" && intervalStr != "") {
                key := StrLower(key)  ; 转换为小写
                interval := Integer(intervalStr)
                
                if (interval > 0) {
                    AddKey(key, interval)
                }
            }
        }
    } catch as err {
        ; 如果读取失败，不影响现有配置
        ; 可以在这里添加错误日志
    }
    
    UpdateOSD()
}

/**
 * 启动配置文件监控（定期检查文件变化）
 */
StartConfigMonitor() {
    ; 每500毫秒检查一次配置文件是否被修改
    SetTimer(CheckConfigFile, 500)
}

/**
 * 检查配置文件是否有变化
 */
CheckConfigFile() {
    global ConfigFileTime
    
    if !FileExist(IniFileName)
        return
    
    try {
        fileTime := FileGetTime(IniFileName, "M")
        ; 如果文件被修改了，重新加载配置
        if (fileTime != ConfigFileTime) {
            LoadConfig()
        }
    }
}

SaveKeyConfig(key, interval) {
    try {
        ; 确保键名是小写
        key := StrLower(key)
        ; 写入配置
        IniWrite interval, IniFileName, "ActiveKeys", key
        ; 更新文件修改时间记录，避免立即触发重载
        global ConfigFileTime
        try {
            ConfigFileTime := FileGetTime(IniFileName, "M")
        }
    } catch {
        ; 保存失败时不影响程序运行
    }
}

; ==============================================================================
; 🖥️ OSD 更新逻辑 (重构版)
; ==============================================================================
UpdateOSD() {
    activeCount := ActiveKeys.Count

    ; --- 1. 更新标题 ---
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
        ; 遍历所有按键，构建显示字符串
        for key, state in ActiveKeys {
            uKey := StrUpper(key)
            
            ; 对齐填充（确保键名对齐）
            padding := ""
            keyLen := StrLen(uKey)
            if (keyLen == 1)
                padding := "  "
            else if (keyLen == 2)
                padding := " "
            
            ; 格式化延迟值（4位数字，右对齐）
            delayValue := Integer(state.BaseDelay)
            delayStr := String(delayValue)
            ; 补空格到4位
            while (StrLen(delayStr) < 4)
                delayStr := " " . delayStr
            
            ; 追加到字符串（使用 .= 确保追加而不是覆盖）
            ; 使用 `n 作为换行符（Edit 控件支持）
            keyListStr .= uKey . padding . " ➜ " . delayStr . " ms`n"
        }
        ; 去掉末尾的换行符
        keyListStr := RTrim(keyListStr, "`n")
        OSDContent.SetFont("cWhite")
    }

    ; --- 3. 更新内容并调整窗口大小 ---
    OSDContent.Value := keyListStr
    
    ; 根据行数动态设置 Edit 控件的高度
    lineCount := activeCount > 0 ? activeCount : 2
    ; 每行大约 20 像素，最小 1 行
    if (lineCount < 1)
        lineCount := 1
    if (lineCount > 20)
        lineCount := 20  ; 限制最大行数
    
    ; 计算所需高度（每行约20像素 + 一些边距）
    height := lineCount * 20 + 6
    
    ; 设置 Edit 控件的宽度和高度
    OSDContent.Move(, , 240, height)
    
    ; 重新显示窗口以应用 AutoSize
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