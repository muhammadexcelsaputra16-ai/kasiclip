import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
export async function middleware(request: NextRequest) {
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL; const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(!url||!key)return NextResponse.redirect(new URL('/login?setup=supabase',request.url));
 let response=NextResponse.next({request});
 const supabase=createServerClient(url,key,{cookies:{getAll(){return request.cookies.getAll();},setAll(cookies: {name:string;value:string;options?:any}[]){cookies.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});cookies.forEach(({name,value,options})=>response.cookies.set(name,value,options));}}});
 const {data:{user}}=await supabase.auth.getUser();
 if(!user)return NextResponse.redirect(new URL('/login',request.url));
 const {data:profile}=await supabase.from('profiles').select('role,account_status').eq('id',user.id).maybeSingle();
 if(!profile||profile.account_status!=='active')return NextResponse.redirect(new URL('/login?status=restricted',request.url));
 const path=request.nextUrl.pathname; const allowed=path.startsWith('/admin')?profile.role==='admin':path.startsWith('/brand')?profile.role==='campaigner':profile.role==='clipper';
 if(!allowed){const destination=profile.role==='admin'?'/admin':profile.role==='campaigner'?'/brand':'/creator';return NextResponse.redirect(new URL(destination,request.url));}
 return response;
}
export const config={matcher:['/creator/:path*','/brand/:path*','/admin/:path*']};
