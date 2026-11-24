"""国家命名：国旗 emoji → 中文国名 → 代码 token → ip-api；CF 段一律 unknown。"""

import ipaddress
import re
import time
import urllib.request
import json

# Cloudflare 公开 IP 段（IPv4 + IPv6）：命中即 unknown，不查 ip-api，不编造国家。
CF_NETWORKS = [
    "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "104.16.0.0/13",
    "104.24.0.0/14", "108.162.192.0/18", "131.0.72.0/22", "141.101.64.0/18",
    "162.158.0.0/15", "172.64.0.0/13", "173.245.48.0/20", "188.114.96.0/20",
    "190.93.240.0/20", "197.234.240.0/22", "198.41.128.0/17",
    "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32",
    "2a06:98c0::/32", "2c0f:f248::/32",
]
_CF = [ipaddress.ip_network(n) for n in CF_NETWORKS]

CODE_TO_CN = {
    "HK": "香港", "US": "美国", "JP": "日本", "KR": "韩国", "SG": "新加坡",
    "GB": "英国", "DE": "德国", "FR": "法国", "CA": "加拿大", "AU": "澳大利亚",
    "TW": "台湾", "NL": "荷兰", "TR": "土耳其", "IN": "印度", "BR": "巴西",
    "RU": "俄罗斯", "UA": "乌克兰", "PL": "波兰", "CH": "瑞士", "SE": "瑞典",
    "NO": "挪威", "FI": "芬兰", "DK": "丹麦", "IT": "意大利", "ES": "西班牙",
    "VN": "越南", "TH": "泰国", "MY": "马来西亚", "ID": "印度尼西亚", "PH": "菲律宾",
    "AE": "阿联酋", "IL": "以色列", "ZA": "南非", "MX": "墨西哥", "AR": "阿根廷",
    "CL": "智利", "CO": "哥伦比亚", "PE": "秘鲁", "NZ": "新西兰", "IE": "爱尔兰",
    "AT": "奥地利", "BE": "比利时", "CZ": "捷克", "GR": "希腊", "PT": "葡萄牙",
    "RO": "罗马尼亚", "HU": "匈牙利", "HR": "克罗地亚", "SI": "斯洛文尼亚",
    "LT": "立陶宛", "LV": "拉脱维亚", "EE": "爱沙尼亚", "IS": "冰岛",
    "LU": "卢森堡", "CY": "塞浦路斯", "MT": "马耳他", "EG": "埃及",
    "NG": "尼日利亚", "KE": "肯尼亚", "SA": "沙特", "QA": "卡塔尔",
    "KW": "科威特", "BH": "巴林", "OM": "阿曼", "JO": "约旦", "LB": "黎巴嫩",
    "IQ": "伊拉克", "IR": "伊朗", "AF": "阿富汗", "PK": "巴基斯坦",
    "BD": "孟加拉", "LK": "斯里兰卡", "NP": "尼泊尔", "MM": "缅甸",
    "KH": "柬埔寨", "LA": "老挝", "MN": "蒙古", "KP": "朝鲜", "BN": "文莱",
    "TL": "东帝汶", "PG": "巴布亚新几内亚", "FJ": "斐济", "MD": "摩尔多瓦",
    "GE": "格鲁吉亚", "AM": "亚美尼亚", "AZ": "阿塞拜疆", "KZ": "哈萨克斯坦",
    "UZ": "乌兹别克斯坦", "KG": "吉尔吉斯斯坦", "TJ": "塔吉克斯坦",
    "TM": "土库曼斯坦", "BY": "白俄罗斯", "AL": "阿尔巴尼亚", "BA": "波黑",
    "RS": "塞尔维亚", "ME": "黑山", "MK": "北马其顿", "BG": "保加利亚",
    "SK": "斯洛伐克",
}
CN_TO_CODE = {}
for _code, _cn in CODE_TO_CN.items():
    CN_TO_CODE[_cn] = _code
# 常见别名
CN_TO_CODE.update({"中国香港": "HK", "中国台湾": "TW", "英国": "GB", "美国": "US"})

REGIONAL_BASE = 0x1F1E6


def flag_to_code(text):
    if not text:
        return None
    points = [ord(c) for c in text]
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        if REGIONAL_BASE <= a <= REGIONAL_BASE + 25 and REGIONAL_BASE <= b <= REGIONAL_BASE + 25:
            return chr(ord("A") + a - REGIONAL_BASE) + chr(ord("A") + b - REGIONAL_BASE)
    return None


def code_to_flag(code):
    if not code or len(code) != 2:
        return ""
    a, b = code.upper()
    if not ("A" <= a <= "Z" and "A" <= b <= "Z"):
        return ""
    return chr(REGIONAL_BASE + ord(a) - ord("A")) + chr(REGIONAL_BASE + ord(b) - ord("A"))


def hint_to_code(name_hint):
    """从源名字里提取国家代码：国旗 → 中文国名 → 代码 token。"""
    if not name_hint:
        return None
    code = flag_to_code(name_hint)
    if code:
        return code
    for cn, c in sorted(CN_TO_CODE.items(), key=lambda kv: -len(kv[0])):
        if cn in name_hint:
            return c
    tokens = re.findall(r"\b([A-Z]{2})\b", name_hint.upper())
    for t in tokens:
        if t in CODE_TO_CN:
            return t
    return None


def is_cf_or_reserved(host):
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
        return True
    return any(ip in net for net in _CF)


class IpApi:
    """带缓存与节流的 ip-api 查询（免费档 45 次/分钟，节流 1.5 秒）。"""

    def __init__(self, throttle=1.5):
        self.cache = {}
        self.throttle = throttle
        self.last = 0.0

    def country(self, host):
        if host in self.cache:
            return self.cache[host]
        if is_cf_or_reserved(host):
            self.cache[host] = (None, None)
            return (None, None)
        wait = self.throttle - (time.time() - self.last)
        if wait > 0:
            time.sleep(wait)
        self.last = time.time()
        try:
            req = urllib.request.Request(
                "http://ip-api.com/json/%s?fields=status,country,countryCode" % host,
                headers={"User-Agent": "free-node-program/1.0"})
            with urllib.request.urlopen(req, timeout=5) as r:
                d = json.loads(r.read().decode("utf-8", errors="ignore"))
            if d.get("status") == "success" and d.get("countryCode"):
                out = (d["countryCode"].upper(), d.get("country") or "")
            else:
                out = (None, None)
        except Exception:
            out = (None, None)
        self.cache[host] = out
        return out


def display_name(code, english_name=""):
    """返回 (中文或英文显示名, 国旗)。code 为 None 时返回 ('未知', '')。"""
    if not code:
        return ("未知", "")
    flag = code_to_flag(code)
    if code in CODE_TO_CN:
        return (CODE_TO_CN[code], flag)
    if english_name:
        return (english_name, flag)
    return (code, flag)
