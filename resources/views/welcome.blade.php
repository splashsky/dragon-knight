<x-guest-layout>
    <x-slot name="pageTitle">Welcome</x-slot>

    <div class="w-1/3 mx-auto">
        <h1 class="text-3xl text-center font-bold my-8">Dragon Knight</h1>
        
        <div class="text-center">
            <a href="{{ route('login') }}"><x-button>Login</x-button></a>
            <a href="{{ route('register') }}"><x-button>Register</x-button></a>
        </div>
    </div>
</x-guest-layout>