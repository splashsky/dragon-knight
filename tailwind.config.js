/** @type {import('tailwindcss').Config} */
const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
    content: ["./views/**/*.template"],
    theme: {
        extend: {
            fontFamily: {
                'serif': ['Vollkorn', ...defaultTheme.fontFamily.serif],
            },
        },
    },
    plugins: [],
}

