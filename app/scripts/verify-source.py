#!/usr/bin/env python3
"""静态源文件/工程与演示清单约束，不是 tvOS 运行测试。"""
import json, pathlib, re, urllib.parse, xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
project = root / 'SuperTV.xcodeproj/project.pbxproj'
assert project.is_file(), '缺少 Xcode 工程骨架'
pbx = project.read_text()
project_ids = set(re.findall(r'^\s*([A-F0-9]{24})\s*=\s*\{', pbx, re.M))
assert project_ids and set(re.findall(r'\b[A-F0-9]{24}\b', pbx)) == project_ids
assert 'SDKROOT = appletvos;' in pbx and 'TARGETED_DEVICE_FAMILY = 3;' in pbx
scheme = ET.parse(root / 'SuperTV.xcodeproj/xcshareddata/xcschemes/SuperTV.xcscheme')
for ref in scheme.findall('.//BuildableReference'):
    assert ref.attrib['BlueprintIdentifier'] in project_ids
    assert ref.attrib['ReferencedContainer'] == 'container:SuperTV.xcodeproj'
for src in sorted((root/'SuperTV').glob('*.swift')):
    assert src.name in pbx, src.name
assert {p.name for p in (root/'SuperTV').glob('*.swift')} >= {'SuperTVApp.swift','Catalog.swift','Player.swift'}
assert 'DemoCatalog.json' in pbx
catalog = json.loads((root/'SuperTV/DemoCatalog.json').read_text())
shows = catalog['shows']; assert shows and len(shows[0]['episodes']) >= 2
assert len({s['id'] for s in shows}) == len(shows)
for show in shows:
    assert '演示' in show['title']
    episodes = show['episodes']; assert episodes and len({e['id'] for e in episodes}) == len(episodes)
    for e in episodes:
        u = urllib.parse.urlsplit(e['streamURL'])
        assert u.scheme == 'https' and u.hostname and u.hostname.endswith('.apple.com')
        assert u.path.endswith('.m3u8') and not u.query and not u.fragment and not u.username
print('PASS: 工程引用、tvOS 目标、内置演示清单与片源范围（静态）')
mac = ET.parse(root / 'SuperTV.xcodeproj/xcshareddata/xcschemes/SuperTV-macOS.xcscheme')
assert 'SDKROOT = macosx;' in pbx and 'MACOSX_DEPLOYMENT_TARGET = 14.0;' in pbx
assert 'UITestSuperTV.swift' in pbx and scheme.find('.//TestableReference') is not None
mac_target = {r.get('BlueprintIdentifier') for r in mac.findall('.//BuildableReference')}
tv_target = {r.get('BlueprintIdentifier') for r in scheme.findall('.//BuildableReference')}
assert mac_target and mac_target <= project_ids and mac_target.isdisjoint(tv_target)
assert re.search(r'lastKnownFileType = folder; path = Offline;', pbx)
media = sorted((root/'SuperTV/Offline').glob('*.mp4'))
assert len(media) == 2 and all(p.stat().st_size > 100_000 for p in media)
assert media[0].read_bytes() != media[1].read_bytes()
print('PASS: 双端 scheme、tvOS UI 目标、离线资源（静态）')
