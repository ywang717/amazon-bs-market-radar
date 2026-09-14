export const generatedCategoryRegistry = {
  "categories": [
    {
      "categoryKey": "pressure_washers",
      "defaults": {
        "alerts": "machines",
        "brands": "machines",
        "data_status": "machines",
        "market": "machines",
        "overview": "machines",
        "product_detail": "machines",
        "products": "machines",
        "rankings": "all",
        "reports": "machines"
      },
      "enabled": true,
      "labelEn": "Pressure Washers",
      "labelZh": "高压清洗机",
      "nodeId": "552856",
      "reportFileToken": "Pressure_Washers",
      "segments": [
        {
          "key": "all",
          "labelZh": "全部榜单",
          "productTypes": []
        },
        {
          "key": "machines",
          "labelZh": "整机",
          "productTypes": [
            "electric_pressure_washer",
            "gas_pressure_washer",
            "cordless_pressure_washer"
          ]
        },
        {
          "key": "electric",
          "labelZh": "电动",
          "productTypes": [
            "electric_pressure_washer"
          ]
        },
        {
          "key": "gas",
          "labelZh": "燃油",
          "productTypes": [
            "gas_pressure_washer"
          ]
        },
        {
          "key": "cordless",
          "labelZh": "无线",
          "productTypes": [
            "cordless_pressure_washer"
          ]
        }
      ],
      "slug": "pressure-washer",
      "sourceUrl": "https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washers/zgbs/lawn-garden/552856",
      "targetCount": 30
    },
    {
      "categoryKey": "sump_pumps",
      "defaults": {
        "alerts": "all",
        "brands": "all",
        "data_status": "all",
        "market": "all",
        "overview": "all",
        "product_detail": "all",
        "products": "all",
        "rankings": "all",
        "reports": "all"
      },
      "enabled": true,
      "labelEn": "Sump Pumps",
      "labelZh": "污水泵",
      "nodeId": "680335011",
      "reportFileToken": "Sump_Pumps",
      "segments": [
        {
          "key": "all",
          "labelZh": "全部榜单",
          "productTypes": []
        }
      ],
      "slug": "sump-pump",
      "sourceUrl": "https://www.amazon.com/Best-Sellers-Tools-Home-Improvement-Sump-Pumps/zgbs/hi/680335011",
      "targetCount": 30
    },
    {
      "categoryKey": "pressure_washer_accessories",
      "defaults": {
        "alerts": "all",
        "brands": "all",
        "data_status": "all",
        "market": "all",
        "overview": "all",
        "product_detail": "all",
        "products": "all",
        "rankings": "all",
        "reports": "all"
      },
      "enabled": true,
      "labelEn": "Pressure Washer Parts & Accessories",
      "labelZh": "高压清洗机配件",
      "nodeId": "3023451",
      "reportFileToken": "Pressure_Washer_Parts_Accessories",
      "segments": [
        {
          "key": "all",
          "labelZh": "全部榜单",
          "productTypes": []
        },
        {
          "key": "surface_cleaners",
          "labelZh": "表面清洁器",
          "productTypes": [
            "surface_cleaner"
          ]
        },
        {
          "key": "guns",
          "labelZh": "喷枪",
          "productTypes": [
            "pressure_washer_gun"
          ]
        },
        {
          "key": "hoses",
          "labelZh": "软管",
          "productTypes": [
            "hose"
          ]
        },
        {
          "key": "nozzles",
          "labelZh": "喷嘴",
          "productTypes": [
            "nozzle"
          ]
        },
        {
          "key": "other",
          "labelZh": "其他配件",
          "productTypes": [
            "foam_cannon",
            "adapter_connector",
            "extension_wand",
            "sewer_jetter",
            "chemical_cleaner",
            "pump_protector",
            "other_accessory"
          ]
        }
      ],
      "slug": "pressure-washer-accessories",
      "sourceUrl": "https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washer-Parts-Accessories/zgbs/lawn-garden/3023451",
      "targetCount": 30
    }
  ],
  "marketplace": {
    "contextCode": "US",
    "storageCode": "AMAZON_US"
  },
  "productTypeAttributes": {
    "adapter_connector": [
      "接口尺寸"
    ],
    "chemical_cleaner": [],
    "cordless_pressure_washer": [
      "工作压力",
      "流量",
      "动力类型",
      "电压",
      "软管长度"
    ],
    "electric_pressure_washer": [
      "工作压力",
      "流量",
      "动力类型",
      "软管长度",
      "电源线长度"
    ],
    "extension_wand": [
      "接口尺寸"
    ],
    "foam_cannon": [
      "接口尺寸"
    ],
    "gas_pressure_washer": [
      "工作压力",
      "流量",
      "动力类型",
      "马力",
      "软管长度"
    ],
    "hose": [
      "软管长度",
      "接口尺寸"
    ],
    "nozzle": [
      "喷嘴角度",
      "接口尺寸"
    ],
    "other_accessory": [
      "接口尺寸"
    ],
    "pressure_washer_gun": [
      "接口尺寸"
    ],
    "pump_protector": [],
    "sewer_jetter": [
      "软管长度",
      "接口尺寸"
    ],
    "surface_cleaner": [
      "接口尺寸"
    ],
    "unknown": []
  },
  "schemaVersion": "category-registry-v1"
} as const;

export type CategoryKey = (typeof generatedCategoryRegistry.categories)[number]["categoryKey"];
export type SegmentKey = (typeof generatedCategoryRegistry.categories)[number]["segments"][number]["key"];
