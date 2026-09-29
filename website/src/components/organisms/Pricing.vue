<script setup lang="ts">
import { shallowRef } from "vue";

const rows = shallowRef([
    { feature: "Email aliases", free: "5", paid: "Unlimited" },
    { feature: "Tracker removal", free: "Yes", paid: "Yes" },
    { feature: "Spam filtering", free: "Yes", paid: "Yes" },
    { feature: "Forward to your inbox", free: "Yes", paid: "Yes" },
    { feature: "Custom domains", free: "—", paid: "Yes" },
    { feature: "Send & reply from aliases", free: "—", paid: "Yes" },
    { feature: "Priority support", free: "—", paid: "Yes" },
    { feature: "Price", free: "£0", freeWorld: "$0", paid: "£25/year", paidWorld: "$35/year" },
]);
// Should be an even number to look nice
const questions = shallowRef([
    {
        question: "Do you have any discounts?",
        answer: "If you're an activist or journalist, get in touch on hello@shroud.email and we'll see what we can do.",
    },
    {
        question: "What happens if I cancel my subscription?",
        answer: "The service will continue for the remainder of the billing period. Then, you won't be able to create new aliases. All your existing aliases will continue to work.",
    },
    {
        question: "What payment methods do you support?",
        answer: "We support Visa, Mastercard, American Express, Discover, Diners Club, China UnionPay (CUP), and Japan Credit Bureau (JCB).",
    },
    {
        question: "What's your refund policy?",
        answer: "We offer a free plan with no time limit, so you can try Shroud.email for as long as you like before upgrading. We don't offer refunds on paid plans.",
    },
    {
        question: "Does Shroud.email forward attachments?",
        answer: "Yes, we forward attachments up to 25MB.",
    },
    {
        question: "Is Shroud.email a disposable email service?",
        answer: "Email aliases are permanent, but you can always disable or delete them if you don't want to receive emails through them any longer.",
    },
]);
</script>

<template>
    <div class="pt-12">
        <div class="bg-slate-50 dark:bg-slate-900">
            <div class="pt-12 sm:pt-16 lg:pt-20">
                <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                    <div class="text-center">
                        <h1
                            class="text-3xl font-medium text-slate-900 sm:text-4xl lg:text-5xl font-display dark:text-slate-50"
                        >
                            Free forever, or <span data-price data-price-world="$35/year">£25/year</span> for the works
                        </h1>
                        <p
                            class="mt-4 text-xl text-slate-600 dark:text-slate-400"
                        >
                            Start on the free plan with 5 aliases. Upgrade when
                            you need unlimited aliases and custom domains.
                        </p>
                    </div>
                </div>
            </div>
            <div
                class="mt-12 bg-white pb-16 sm:mt-16 sm:pb-20 lg:pb-28 dark:bg-slate-950"
            >
                <div class="relative">
                    <div
                        class="absolute inset-0 h-1/2 bg-slate-50 dark:bg-slate-900"
                    ></div>
                    <div
                        class="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8"
                    >
                        <div
                            class="max-w-5xl mx-auto rounded-lg shadow-lg overflow-hidden ring-1 ring-slate-200/60 dark:ring-white/10"
                        >
                            <div
                                class="overflow-x-auto bg-white dark:bg-slate-900"
                            >
                                <table class="w-full text-left">
                                    <thead>
                                        <tr
                                            class="border-b border-slate-200 dark:border-slate-800"
                                        >
                                            <th
                                                class="py-5 px-4 sm:px-6 text-sm font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400"
                                            >
                                                Feature
                                            </th>
                                            <th
                                                class="py-5 px-4 sm:px-6 text-sm font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400 text-center"
                                            >
                                                Free
                                            </th>
                                            <th
                                                class="py-5 px-4 sm:px-6 text-sm font-semibold uppercase tracking-wider text-indigo-600 dark:text-indigo-400 text-center"
                                            >
                                                Paid yearly
                                            </th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <tr
                                            v-for="row in rows"
                                            :key="row.feature"
                                            class="border-b border-slate-100 dark:border-slate-800 last:border-0"
                                        >
                                            <td
                                                class="py-4 px-4 sm:px-6 text-sm font-medium text-slate-900 dark:text-slate-100"
                                            >
                                                {{ row.feature }}
                                            </td>
                                            <td
                                                class="py-4 px-4 sm:px-6 text-sm text-slate-700 dark:text-slate-300 text-center"
                                            >
                                                <span :data-price="row.freeWorld ? '' : undefined" :data-price-world="row.freeWorld || undefined">{{ row.free }}</span>
                                            </td>
                                            <td
                                                class="py-4 px-4 sm:px-6 text-sm text-slate-700 dark:text-slate-300 text-center"
                                            >
                                                <span :data-price="row.paidWorld ? '' : undefined" :data-price-world="row.paidWorld || undefined">{{ row.paid }}</span>
                                            </td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                            <div
                                class="bg-white px-6 py-8 text-center dark:bg-slate-900"
                            >
                                <div
                                    class="mt-2 flex flex-col sm:flex-row gap-3 justify-center"
                                >
                                    <a
                                        href="https://app.shroud.email/users/register"
                                        class="inline-flex items-center justify-center px-5 py-3 border border-transparent text-base font-medium rounded-md text-white bg-slate-900 hover:bg-slate-950 dark:bg-indigo-500 dark:hover:bg-indigo-400"
                                    >
                                        Start free
                                    </a>
                                    <a
                                        href="https://app.shroud.email/settings/billing"
                                        class="inline-flex items-center justify-center px-5 py-3 border border-slate-300 dark:border-slate-700 text-base font-medium rounded-md text-slate-900 dark:text-slate-100 hover:bg-slate-50 dark:hover:bg-slate-800"
                                    >
                                        Upgrade to paid
                                    </a>
                                </div>
                                <p
                                    class="mt-4 text-sm text-slate-500 dark:text-slate-400"
                                >
                                    No credit card needed for the free plan.
                                </p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="bg-slate-950">
            <div class="max-w-7xl mx-auto py-16 px-4 sm:py-24 sm:px-6 lg:px-8">
                <div class="lg:max-w-2xl lg:mx-auto lg:text-center">
                    <h2
                        class="text-3xl font-bold tracking-tight text-white sm:text-4xl font-display"
                    >
                        Frequently asked questions
                    </h2>
                    <p class="mt-4 text-slate-300">
                        If your question isn't answered here, please
                        <a href="mailto:hello@shroud.email" class="underline"
                            >contact us.</a
                        >
                    </p>
                </div>
                <div class="mt-20">
                    <dl
                        class="space-y-10 lg:space-y-0 lg:grid lg:grid-cols-2 lg:gap-x-8 lg:gap-y-10"
                    >
                        <div
                            v-for="{ question, answer } in questions"
                            :key="question"
                        >
                            <dt class="font-semibold text-white">
                                {{ question }}
                            </dt>
                            <dd class="mt-3 text-slate-300">
                                {{ answer }}
                            </dd>
                        </div>
                    </dl>
                </div>
            </div>
        </div>
    </div>
</template>
