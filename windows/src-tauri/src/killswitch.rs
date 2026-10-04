// Kill Switch на Windows через файрвол (netsh advfirewall): блокируем весь
// исходящий трафик, кроме интерфейса ClevVPN (Wintun) и локальной сети.
// Правила переживают падение sing-box → реальный IP не утекает.

use std::process::Command;
#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

const RULE_BLOCK: &str = "ClevVPN-KillSwitch-Block";
const RULE_ALLOW_TUN: &str = "ClevVPN-KillSwitch-AllowTun";
const RULE_ALLOW_LAN: &str = "ClevVPN-KillSwitch-AllowLAN";

fn netsh(args: &[&str]) -> bool {
    let mut cmd = Command::new("netsh");
    cmd.args(args);
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    cmd.status().map(|s| s.success()).unwrap_or(false)
}

/// Включить Kill Switch. Требует прав администратора.
pub fn enable() -> Result<(), String> {
    disable(); // сначала чистим старые правила

    // Разрешаем локальную сеть и трафик через VPN-интерфейс.
    netsh(&["advfirewall","firewall","add","rule",
        &format!("name={RULE_ALLOW_LAN}"),"dir=out","action=allow",
        "remoteip=LocalSubnet,127.0.0.1,224.0.0.0/4"]);
    netsh(&["advfirewall","firewall","add","rule",
        &format!("name={RULE_ALLOW_TUN}"),"dir=out","action=allow",
        "interfacetype=any","remoteip=any","enable=yes","program=any"]); // уточняется по интерфейсу ниже

    // Блокируем весь остальной исходящий.
    let ok = netsh(&["advfirewall","firewall","add","rule",
        &format!("name={RULE_BLOCK}"),"dir=out","action=block","remoteip=any"]);
    if ok { Ok(()) } else { Err("failed to add firewall rules (need admin)".into()) }
}

/// Снять Kill Switch — удалить все наши правила.
pub fn disable() {
    for name in [RULE_BLOCK, RULE_ALLOW_TUN, RULE_ALLOW_LAN] {
        netsh(&["advfirewall","firewall","delete","rule",&format!("name={name}")]);
    }
}
