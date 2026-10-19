import { ReviewEditor } from "./review-editor";
import { gardenRegistryCategories } from "@/lib/garden-data";
export default function GardenReviewPage(){return <><h2>市场可销售性核验</h2><p>公开读取仅显示已发布核验。保存需要已有同步凭证，凭证只保存在当前页面内存中。</p><ReviewEditor categories={gardenRegistryCategories().map(c=>({key:c.categoryKey,label:c.labelZh}))}/></>;}
