# USB DriverKit Entitlement Candidates

These catalog identities are candidates for a future Apple USB DriverKit entitlement application.

Raw USB controllers use one of two access backends. The `usb-driverkit` backend covers the identities in the checked-in DEXT entitlement and personality: seven Microsoft GIP identities, `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12` (`Sources/OpenJoystickDriverUSB/Configuration.swift`). Every other raw USB controller uses the `iousbhost` backend.

The identities below pass the catalog's raw-USB parser predicate (`DeviceCatalog.supportsRawUSBPipeline`: `usb` transport with a `GIP`, `XUSB`, `XID`, or `GameSir` driver) and use `iousbhost`. The owner decided not to re-apply for entitlement coverage now, because re-adding every identity can take weeks. Moving an identity to `usb-driverkit` needs that coverage.

Listing an identity here does not mean it was observed on hardware. Each one is a conditional catalog candidate from the generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/`. When the catalog changes, recompute the list with the same predicate.

To move an identity to `usb-driverkit`: obtain Apple-issued USB transport entitlement coverage, add the pair to the DEXT configuration and entitlement, pass the signing-profile validation in `Scripts/Build/driverkit.sh`, and record hardware results under `contributing/testing/`.

## GIP (77)

| VID | PIDs |
| --- | --- |
| `03F0` | 0495, 07A0, 08B6, 09B4 |
| `044F` | D01E |
| `0738` | 4503, 4A01 |
| `0B05` | 1A38, 1ABB, 1C96, 1D04 |
| `0E6F` | 0139, 013A, 0146, 0147, 015C, 015D, 0161, 0162, 0163, 0164, 0165, 0246, 02A0, 02A1, 02A2, 02A4, 02A6, 02A7, 02A8, 02AB, 02AD, 02B3, 02B8, 0346 |
| `0F0D` | 0063, 0067, 0078, 00C5, 0151, 0152, 01B2 |
| `10F5` | 7005, 7008, 7073 |
| `1532` | 0A00, 0A03, 0A29, 0A3F, 0A43 |
| `20D6` | 2001, 2009, 2064, 400B, 890B |
| `24C6` | 541A, 542A, 543A, 551A, 561A, 581A |
| `294B` | 3303, 3404 |
| `2DC8` | 2000, 200F |
| `2E24` | 0423, 0652, 1688 |
| `2E95` | 0504 |
| `3285` | 0603, 0614, 0634, 0646, 0663 |
| `3537` | 1010, 1022 |
| `37D7` | 2801 |

## XUSB (165)

| VID | PIDs |
| --- | --- |
| `0079` | 18D4 |
| `0351` | 1000, 2000 |
| `03EB` | FF01, FF02 |
| `03F0` | 038D, 048D |
| `044F` | B326 |
| `045E` | 028E, 028F, 0291, 02A9, 0719 |
| `046D` | C21D, C21E, C21F, C242, CAA3 |
| `0502` | 1305 |
| `056E` | 2004 |
| `06A3` | F51A |
| `0738` | 4716, 4718, 4726, 4728, 4736, 4738, 4740, 4758, 9871, B726, B738, BEEF, CB02, CB03, CB29, F738 |
| `07FF` | FFFF |
| `0B05` | 1C91, 1C92 |
| `0DB0` | 1901 |
| `0E6F` | 0105, 0113, 011F, 0131, 0133, 0201, 0213, 021F, 0301, 0401, 0413, 0501, F900 |
| `0F0D` | 000A, 000C, 000D, 0016, 001B, 00DC |
| `1038` | 1430, 1431 |
| `11C9` | 55F0 |
| `11FF` | 0511 |
| `1209` | 2882 |
| `12AB` | 0004, 0301, 0303 |
| `1430` | 4748, F801 |
| `146B` | 0601, 0604 |
| `1532` | 0A57, 0A59 |
| `15E4` | 3F00, 3F0A, 3F10 |
| `162E` | BEEF |
| `1689` | FD00, FD01, FE00 |
| `17EF` | 6182 |
| `1949` | 041A |
| `1A86` | E310 |
| `1BAD` | 0002, 0003, 0130, F016, F018, F019, F021, F023, F025, F027, F028, F02E, F030, F036, F038, F039, F03A, F03D, F03E, F03F, F042, F080, F501, F502, F503, F504, F505, F506, F900, F901, F903, F904, F906, FA01, FD00, FD01 |
| `1EE9` | 1590 |
| `20BC` | 5134, 514A |
| `20D6` | 281F |
| `2345` | E00B |
| `24C6` | 5000, 5300, 5303, 530A, 531A, 5397, 5500, 5501, 5502, 5503, 5506, 550D, 550E, 5510, 5B00, 5B02, 5B03, 5D04, FAFE |
| `2563` | 058D |
| `2993` | 2001 |
| `2DC8` | 3106, 3109, 310A, 310B, 6001 |
| `31E3` | 1100, 1200, 1210, 1220, 1230, 1300, 1310 |
| `3285` | 0607, 0662 |
| `3537` | 1004, 100F |
| `3651` | 1000 |
| `37D7` | 2501 |
| `413D` | 2104 |

## XID (59)

| VID | PIDs |
| --- | --- |
| `044F` | 0F00, 0F03, 0F07, 0F10 |
| `045E` | 0202, 0285, 0287, 0288, 0289 |
| `046D` | CA84, CA88, CA8A |
| `05FD` | 1007, 107A |
| `05FE` | 3030, 3031 |
| `062A` | 0020, 0033 |
| `06A3` | 0200, 0201 |
| `0738` | 4506, 4516, 4520, 4522, 4526, 4530, 4536, 4540, 4556, 4586, 4588, 45FF, 4743, 6040 |
| `0C12` | 0005, 8801, 8802, 8809, 880A, 8810, 9902 |
| `0D2F` | 0002 |
| `0E4C` | 1097, 1103, 2390, 3510 |
| `0E6F` | 0003, 0005, 0006, 0008 |
| `0E8F` | 0201, 3008 |
| `0F30` | 010B, 0202, 8888 |
| `102C` | FF0C |
| `12AB` | 8809 |
| `1430` | 8888 |
| `3767` | 0101 |

## GameSir (6)

| VID | PIDs |
| --- | --- |
| `3537` | 1003, 105D, 105E, 109B, 109C, 10BA |
