#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_PATH="${SCRIPT_DIR}/complex_foundry_circuit_reference.png"

FILTER_GRAPH="$(cat <<'EOF'
drawbox=x=0:y=0:w=2600:h=1500:color=0x0b1020:t=fill,
drawbox=x=30:y=30:w=2540:h=1440:color=0x111b33:t=fill,
drawbox=x=30:y=30:w=2540:h=1440:color=0x2b3a61:t=3,
drawbox=x=30:y=30:w=2540:h=120:color=0x162447:t=fill,
drawtext=text='SchroSIM Foundry Circuit Reference (Compliant Hybrid Pattern)':x=60:y=62:fontsize=46:fontcolor=white,
drawtext=text='Profile enterprise-default-v2  |  Backend hybrid_auto  |  Modes 6  |  Slots 13':x=60:y=108:fontsize=28:fontcolor=0xc7d2fe,

drawbox=x=2200:y=170:w=340:h=1240:color=0x0f172a:t=fill,
drawbox=x=2200:y=170:w=340:h=1240:color=0x334155:t=2,
drawtext=text='Foundry Constraints':x=2230:y=210:fontsize=34:fontcolor=white,
drawtext=text='max_modes 6':x=2230:y=270:fontsize=24:fontcolor=0xbfdbfe,
drawtext=text='max_squeezing_r 1.50':x=2230:y=310:fontsize=24:fontcolor=0xbfdbfe,
drawtext=text='allow_non_gaussian true':x=2230:y=350:fontsize=24:fontcolor=0xbfdbfe,
drawtext=text='allow_measurements true':x=2230:y=390:fontsize=24:fontcolor=0xbfdbfe,
drawtext=text='inject_mode_loss true':x=2230:y=430:fontsize=24:fontcolor=0xbfdbfe,
drawtext=text='mode_loss_eta [0.995..]':x=2230:y=470:fontsize=24:fontcolor=0xbfdbfe,
drawtext=text='RBAC Run Role approver':x=2230:y=540:fontsize=24:fontcolor=0xfde68a,
drawtext=text='Trace Role editor':x=2230:y=580:fontsize=24:fontcolor=0xfde68a,
drawtext=text='Contraction hybrid_auto':x=2230:y=620:fontsize=24:fontcolor=0xfde68a,
drawtext=text='Seed 314159':x=2230:y=660:fontsize=24:fontcolor=0xfde68a,
drawtext=text='Provenance signed profile':x=2230:y=700:fontsize=24:fontcolor=0x86efac,
drawtext=text='Expected flow':x=2230:y=770:fontsize=28:fontcolor=white,
drawtext=text='1) Prepare multimode sources':x=2230:y=815:fontsize=22:fontcolor=0xe2e8f0,
drawtext=text='2) Entangle via BS mesh':x=2230:y=850:fontsize=22:fontcolor=0xe2e8f0,
drawtext=text='3) Add realistic channels':x=2230:y=885:fontsize=22:fontcolor=0xe2e8f0,
drawtext=text='4) Inject GKP ancilla (hybrid-safe)':x=2230:y=920:fontsize=22:fontcolor=0xe2e8f0,
drawtext=text='5) Measure + classical control':x=2230:y=955:fontsize=22:fontcolor=0xe2e8f0,
drawtext=text='6) Export + trace replay':x=2230:y=990:fontsize=22:fontcolor=0xe2e8f0,

drawbox=x=260:y=170:w=1890:h=1240:color=0x0b1328:t=fill,
drawbox=x=260:y=170:w=1890:h=1240:color=0x334155:t=2,

drawbox=x=360:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=500:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=640:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=780:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=920:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1060:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1200:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1340:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1480:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1620:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1760:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=1900:y=190:w=2:h=1170:color=white@0.10:t=fill,
drawbox=x=2040:y=190:w=2:h=1170:color=white@0.10:t=fill,

drawtext=text='t0':x=350:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t1':x=490:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t2':x=630:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t3':x=770:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t4':x=910:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t5':x=1050:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t6':x=1190:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t7':x=1330:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t8':x=1470:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t9':x=1610:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t10':x=1742:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t11':x=1882:y=182:fontsize=20:fontcolor=0x94a3b8,
drawtext=text='t12':x=2022:y=182:fontsize=20:fontcolor=0x94a3b8,

drawbox=x=300:y=240:w=1820:h=3:color=white@0.45:t=fill,
drawbox=x=300:y=420:w=1820:h=3:color=white@0.45:t=fill,
drawbox=x=300:y=600:w=1820:h=3:color=white@0.45:t=fill,
drawbox=x=300:y=780:w=1820:h=3:color=white@0.45:t=fill,
drawbox=x=300:y=960:w=1820:h=3:color=white@0.45:t=fill,
drawbox=x=300:y=1140:w=1820:h=3:color=white@0.45:t=fill,

drawtext=text='Mode 0':x=90:y=224:fontsize=30:fontcolor=0xe2e8f0,
drawtext=text='Mode 1':x=90:y=404:fontsize=30:fontcolor=0xe2e8f0,
drawtext=text='Mode 2':x=90:y=584:fontsize=30:fontcolor=0xe2e8f0,
drawtext=text='Mode 3':x=90:y=764:fontsize=30:fontcolor=0xe2e8f0,
drawtext=text='Mode 4':x=90:y=944:fontsize=30:fontcolor=0xe2e8f0,
drawtext=text='Mode 5':x=90:y=1124:fontsize=30:fontcolor=0xe2e8f0,

drawbox=x=330:y=212:w=96:h=56:color=0x16a34a:t=fill,drawtext=text='|0>':x=356:y=227:fontsize=28:fontcolor=white,
drawbox=x=330:y=392:w=96:h=56:color=0x16a34a:t=fill,drawtext=text='|0>':x=356:y=407:fontsize=28:fontcolor=white,
drawbox=x=330:y=572:w=96:h=56:color=0x16a34a:t=fill,drawtext=text='|0>':x=356:y=587:fontsize=28:fontcolor=white,
drawbox=x=330:y=752:w=96:h=56:color=0x16a34a:t=fill,drawtext=text='|0>':x=356:y=767:fontsize=28:fontcolor=white,
drawbox=x=330:y=932:w=96:h=56:color=0x16a34a:t=fill,drawtext=text='|0>':x=356:y=947:fontsize=28:fontcolor=white,
drawbox=x=330:y=1112:w=96:h=56:color=0x16a34a:t=fill,drawtext=text='|0>':x=356:y=1127:fontsize=28:fontcolor=white,

drawbox=x=470:y=212:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='S(0.8)':x=478:y=227:fontsize=24:fontcolor=white,
drawbox=x=470:y=392:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Rz':x=504:y=407:fontsize=28:fontcolor=white,
drawbox=x=470:y=572:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='D':x=511:y=587:fontsize=30:fontcolor=white,
drawbox=x=470:y=752:w=96:h=56:color=0x7c3aed:t=fill,drawtext=text='gkp':x=498:y=767:fontsize=28:fontcolor=white,
drawbox=x=470:y=932:w=96:h=56:color=0x7c3aed:t=fill,drawtext=text='gkp':x=498:y=947:fontsize=28:fontcolor=white,
drawbox=x=470:y=1112:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Sq':x=495:y=1127:fontsize=28:fontcolor=white,

drawbox=x=750:y=212:w=96:h=56:color=0x0ea5e9:t=fill,drawtext=text='BS':x=782:y=227:fontsize=30:fontcolor=white,
drawbox=x=890:y=572:w=96:h=56:color=0x0ea5e9:t=fill,drawtext=text='BS':x=922:y=587:fontsize=30:fontcolor=white,
drawbox=x=1170:y=932:w=96:h=56:color=0x0ea5e9:t=fill,drawtext=text='BS':x=1202:y=947:fontsize=30:fontcolor=white,

drawbox=x=798:y=240:w=3:h=183:color=0x38bdf8:t=fill,
drawbox=x=938:y=600:w=3:h=183:color=0x38bdf8:t=fill,
drawbox=x=1218:y=960:w=3:h=183:color=0x38bdf8:t=fill,

drawbox=x=1030:y=212:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Rz':x=1064:y=227:fontsize=28:fontcolor=white,
drawbox=x=1030:y=392:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='S':x=1069:y=407:fontsize=30:fontcolor=white,
drawbox=x=1030:y=572:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='D':x=1071:y=587:fontsize=30:fontcolor=white,
drawbox=x=1030:y=752:w=96:h=56:color=0xca8a04:t=fill,drawtext=text='Loss':x=1048:y=767:fontsize=24:fontcolor=white,
drawbox=x=1030:y=932:w=96:h=56:color=0xca8a04:t=fill,drawtext=text='Therm':x=1042:y=947:fontsize=22:fontcolor=white,
drawbox=x=1030:y=1112:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Rz':x=1064:y=1127:fontsize=28:fontcolor=white,

drawbox=x=1310:y=212:w=96:h=56:color=0xca8a04:t=fill,drawtext=text='Loss':x=1328:y=227:fontsize=24:fontcolor=white,
drawbox=x=1310:y=392:w=96:h=56:color=0xca8a04:t=fill,drawtext=text='Therm':x=1322:y=407:fontsize=22:fontcolor=white,
drawbox=x=1310:y=572:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Rz':x=1344:y=587:fontsize=28:fontcolor=white,
drawbox=x=1310:y=752:w=96:h=56:color=0x7c3aed:t=fill,drawtext=text='gkp':x=1338:y=767:fontsize=28:fontcolor=white,
drawbox=x=1310:y=932:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='D':x=1351:y=947:fontsize=30:fontcolor=white,
drawbox=x=1310:y=1112:w=96:h=56:color=0xca8a04:t=fill,drawtext=text='Loss':x=1328:y=1127:fontsize=24:fontcolor=white,

drawbox=x=1730:y=212:w=96:h=56:color=0xdc2626:t=fill,drawtext=text='M_x':x=1752:y=227:fontsize=28:fontcolor=white,
drawbox=x=1730:y=392:w=96:h=56:color=0xdc2626:t=fill,drawtext=text='M_p':x=1752:y=407:fontsize=28:fontcolor=white,
drawbox=x=1730:y=752:w=96:h=56:color=0xdc2626:t=fill,drawtext=text='M_x':x=1752:y=767:fontsize=28:fontcolor=white,
drawbox=x=1730:y=1112:w=96:h=56:color=0xdc2626:t=fill,drawtext=text='M_p':x=1752:y=1127:fontsize=28:fontcolor=white,

drawbox=x=1870:y=572:w=96:h=56:color=0x475569:t=fill,drawtext=text='IF':x=1902:y=587:fontsize=30:fontcolor=white,
drawbox=x=1870:y=932:w=96:h=56:color=0x475569:t=fill,drawtext=text='IF':x=1902:y=947:fontsize=30:fontcolor=white,
drawbox=x=1918:y=448:w=3:h=156:color=0x94a3b8:t=fill,
drawbox=x=1918:y=808:w=3:h=156:color=0x94a3b8:t=fill,
drawtext=text='classical feed-forward':x=1800:y=520:fontsize=18:fontcolor=0xcbd5e1,
drawtext=text='classical feed-forward':x=1800:y=880:fontsize=18:fontcolor=0xcbd5e1,

drawbox=x=2010:y=572:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Rz':x=2044:y=587:fontsize=28:fontcolor=white,
drawbox=x=2010:y=932:w=96:h=56:color=0x2563eb:t=fill,drawtext=text='Rz':x=2044:y=947:fontsize=28:fontcolor=white,

drawbox=x=70:y=1290:w=2080:h=130:color=0x0f172a:t=fill,
drawbox=x=70:y=1290:w=2080:h=130:color=0x334155:t=2,
drawbox=x=100:y=1330:w=38:h=30:color=0x16a34a:t=fill,drawtext=text='Source':x=148:y=1332:fontsize=22:fontcolor=0xe2e8f0,
drawbox=x=360:y=1330:w=38:h=30:color=0x2563eb:t=fill,drawtext=text='Gaussian':x=408:y=1332:fontsize=22:fontcolor=0xe2e8f0,
drawbox=x=650:y=1330:w=38:h=30:color=0x0ea5e9:t=fill,drawtext=text='Inter-mode coupler':x=698:y=1332:fontsize=22:fontcolor=0xe2e8f0,
drawbox=x=1010:y=1330:w=38:h=30:color=0xca8a04:t=fill,drawtext=text='Channel (loss/thermal)':x=1058:y=1332:fontsize=22:fontcolor=0xe2e8f0,
drawbox=x=1390:y=1330:w=38:h=30:color=0x7c3aed:t=fill,drawtext=text='Non-gaussian':x=1438:y=1332:fontsize=22:fontcolor=0xe2e8f0,
drawbox=x=1670:y=1330:w=38:h=30:color=0xdc2626:t=fill,drawtext=text='Measurement':x=1718:y=1332:fontsize=22:fontcolor=0xe2e8f0,
drawbox=x=1940:y=1330:w=38:h=30:color=0x475569:t=fill,drawtext=text='Classical control':x=1988:y=1332:fontsize=22:fontcolor=0xe2e8f0
EOF
)"

ffmpeg -y \
    -f lavfi \
    -i "color=c=0x0b1020:s=2600x1500:d=1" \
    -frames:v 1 \
    -update 1 \
    -vf "${FILTER_GRAPH}" \
    "${OUT_PATH}"

echo "Created ${OUT_PATH}"
